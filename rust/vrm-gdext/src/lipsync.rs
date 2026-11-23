//! 音声ファイル (mp3 / wav / ogg / flac、mp4 / mkv などの動画の音) から、口の動きと感情を前もって求める。
//!
//! 1/60 秒ごとに [open, aa, ih, ou, ee, oh, happy, surprised, sad] を並べた表を作る。
//! - open: 口の開き (音の大きさ。ファイル全体の大きい音を 1 とする)
//! - aa〜oh: 母音の混ざり具合 (合計 1)。滑らかにした周波数の山 (F1 / F2) から、日本語の 5 母音への近さで決める
//! - happy / surprised / sad: 声の高さ・大きさ・抑揚から、軽く見積もる (最大 0.4)
//!
//! AI のモデルは使わない。解析は読み込むときに 1 回だけで、再生中は表を引くだけ。

use rustfft::{FftPlanner, num_complex::Complex};
use std::path::Path;

pub const FPS: f32 = 60.0;
pub const STRIDE: usize = 9;
/// 解析に使うおおよその標本化周波数 (F2 の 3 kHz まで見えれば足りる)
const TARGET_RATE: f32 = 11025.0;
/// 感情の重みの上限
const EMOTION_MAX: f32 = 0.4;
/// 感情を出し始める強さ (これより小さな変化は無視する)
const EMOTION_DEAD: f32 = 0.3;
/// F2 に取る山の強さ (その範囲で一番強い山との比) の下限
const F2_RATIO: f32 = 0.3;

/// 日本語の 5 母音の (F1, F2) の代表値 [Hz]。順は aa, ih, ou, ee, oh
const VOWELS: [(f32, f32); 5] = [(750.0, 1250.0), (300.0, 2250.0), (350.0, 1450.0), (500.0, 1900.0), (500.0, 850.0)];

pub struct Analysis {
    pub duration: f32,
    /// STRIDE 個ずつ並んだ表
    pub frames: Vec<f32>,
}

impl Analysis {
    pub fn frame_count(&self) -> usize {
        self.frames.len() / STRIDE
    }
    pub fn frame(&self, i: usize) -> &[f32] {
        &self.frames[i * STRIDE..(i + 1) * STRIDE]
    }
}

/// 再生用の音 (16 bit、左右が交互に並ぶ)
pub struct Pcm {
    pub samples: Vec<i16>,
    pub rate: u32,
    pub channels: u16,
}

impl Pcm {
    fn new(rate: u32, channels: u16) -> Self {
        Self { samples: Vec::new(), rate, channels }
    }
    fn push_frame(&mut self, fr: &[f32]) {
        // 3 チャンネル以上は、先頭の 2 つ (左右) だけを使う
        for c in 0..self.channels as usize {
            let v = fr.get(c).copied().unwrap_or(0.0);
            self.samples.push((v.clamp(-1.0, 1.0) * 32767.0) as i16);
        }
    }
}

/// 読み込んだ結果。mono / rate は解析用に間引いたもの。pcm は再生用 (頼んだときだけ)
pub struct Decoded {
    pub mono: Vec<f32>,
    pub rate: u32,
    pub pcm: Option<Pcm>,
}

/// ファイルを読んで解析する
pub fn analyze_file(path: &str) -> Result<Analysis, String> {
    analyze_file_with_pcm(path, false).map(|r| r.0)
}

/// ファイルを読んで解析し、keep_pcm なら再生用の音も返す
pub fn analyze_file_with_pcm(path: &str, keep_pcm: bool) -> Result<(Analysis, Option<Pcm>), String> {
    let d = decode_file(path, keep_pcm)?;
    if d.mono.is_empty() || d.rate == 0 {
        return Err("音声が入っていません".into());
    }
    Ok((analyze_samples(&d.mono, d.rate), d.pcm))
}

/// ファイルをモノラルにして、解析用に間引いた標本を返す。
/// symphonia で読めないとき (webm の Opus など) は、FFmpeg があればそれで取り出す。
pub fn decode_file(path: &str, keep_pcm: bool) -> Result<Decoded, String> {
    if !Path::new(path).is_file() {
        return Err(format!("ファイルが見つかりません: {path}"));
    }
    match decode_symphonia(path, keep_pcm) {
        Ok(r) if !r.mono.is_empty() => Ok(r),
        Ok(_) => decode_ffmpeg(path, keep_pcm).map_err(|e| format!("音声が見つかりません ({e})")),
        Err(e1) => decode_ffmpeg(path, keep_pcm).map_err(|e2| format!("音声を読めません: {e1} / FFmpeg: {e2}")),
    }
}

fn decode_symphonia(path: &str, keep_pcm: bool) -> Result<Decoded, String> {
    use symphonia::core::audio::SampleBuffer;
    use symphonia::core::codecs::{CODEC_TYPE_NULL, DecoderOptions};
    use symphonia::core::errors::Error;
    use symphonia::core::formats::FormatOptions;
    use symphonia::core::io::MediaSourceStream;
    use symphonia::core::meta::MetadataOptions;
    use symphonia::core::probe::Hint;

    let file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = Path::new(path).extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|e| e.to_string())?;
    let mut format = probed.format;
    // 音の入っている最初のトラック (動画なら映像のトラックは飛ばす)
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL && t.codec_params.sample_rate.is_some())
        .ok_or("音声のトラックがありません")?;
    let track_id = track.id;
    let rate = track.codec_params.sample_rate.unwrap_or(44100);
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|e| e.to_string())?;
    let mut dec = Decimator::new(rate);
    let mut pcm: Option<Pcm> = None;
    let mut sbuf: Option<SampleBuffer<f32>> = None;
    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(Error::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(Error::ResetRequired) => break,
            Err(e) => return Err(e.to_string()),
        };
        if packet.track_id() != track_id {
            continue;
        }
        match decoder.decode(&packet) {
            Ok(buf) => {
                let spec = *buf.spec();
                let ch = spec.channels.count().max(1);
                if keep_pcm && pcm.is_none() {
                    pcm = Some(Pcm::new(spec.rate, ch.min(2) as u16));
                }
                let need = buf.capacity() as u64;
                if sbuf.as_ref().is_none_or(|b| b.capacity() < need as usize * ch) {
                    sbuf = Some(SampleBuffer::<f32>::new(need, spec));
                }
                let sb = sbuf.as_mut().unwrap();
                sb.copy_interleaved_ref(buf);
                for fr in sb.samples().chunks(ch) {
                    dec.push(fr.iter().sum::<f32>() / ch as f32);
                    if let Some(p) = pcm.as_mut() {
                        p.push_frame(fr);
                    }
                }
            }
            Err(Error::DecodeError(_)) => continue,
            Err(e) => return Err(e.to_string()),
        }
    }
    let (mono, r) = dec.finish();
    Ok(Decoded { mono, rate: r, pcm })
}

/// FFmpeg で 44.1 kHz の 16 bit ステレオにして取り出す (解析用のモノラルもここから作る)
fn decode_ffmpeg(path: &str, keep_pcm: bool) -> Result<Decoded, String> {
    use std::process::{Command, Stdio};
    let rate = 44100u32;
    let mut cmd = Command::new("ffmpeg");
    cmd.args(["-v", "error", "-nostdin", "-i", path, "-vn", "-ac", "2", "-ar", &rate.to_string(), "-f", "s16le", "-"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    let out = cmd.output().map_err(|e| format!("FFmpeg を起動できません: {e}"))?;
    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
    }
    let samples: Vec<i16> = out.stdout.chunks_exact(2).map(|b| i16::from_le_bytes([b[0], b[1]])).collect();
    let mut dec = Decimator::new(rate);
    for fr in samples.chunks_exact(2) {
        dec.push((fr[0] as f32 + fr[1] as f32) / 65534.0);
    }
    let (mono, r) = dec.finish();
    let pcm = keep_pcm.then(|| Pcm { samples, rate, channels: 2 });
    Ok(Decoded { mono, rate: r, pcm })
}

/// 標本を平均して間引く (TARGET_RATE に近づける)
struct Decimator {
    factor: usize,
    rate: u32,
    acc: f32,
    n: usize,
    out: Vec<f32>,
}

impl Decimator {
    fn new(rate: u32) -> Self {
        let factor = ((rate as f32 / TARGET_RATE).round() as usize).max(1);
        Self { factor, rate, acc: 0.0, n: 0, out: Vec::new() }
    }
    fn push(&mut self, s: f32) {
        self.acc += s;
        self.n += 1;
        if self.n == self.factor {
            self.out.push(self.acc / self.factor as f32);
            self.acc = 0.0;
            self.n = 0;
        }
    }
    fn finish(self) -> (Vec<f32>, u32) {
        let r = self.rate / self.factor as u32;
        (self.out, r)
    }
}

/// 標本から解析する。rate は標本化周波数
pub fn analyze_samples(samples: &[f32], rate: u32) -> Analysis {
    let sr = rate as f32;
    let duration = samples.len() as f32 / sr;
    let nframes = ((duration * FPS).ceil() as usize).max(1);
    let win = ((sr * 0.04) as usize).next_power_of_two().max(256);
    let hann: Vec<f32> = (0..win).map(|i| 0.5 - 0.5 * (std::f32::consts::TAU * i as f32 / win as f32).cos()).collect();
    let fft = FftPlanner::<f32>::new().plan_fft_forward(win);
    let bin_hz = sr / win as f32;
    let mut buf = vec![Complex::new(0.0f32, 0.0); win];
    let lpc_order = 2 + (sr / 1000.0) as usize;
    let mut seg = vec![0.0f32; win];

    let mut rms = vec![0.0f32; nframes];
    let mut vowel = vec![[0.2f32; 5]; nframes];
    let mut pitch = vec![0.0f32; nframes]; // 0 = 声ではない
    for i in 0..nframes {
        let center = (i as f32 / FPS * sr) as isize;
        let start = center - win as isize / 2;
        let mut e = 0.0;
        for (k, s) in seg.iter_mut().enumerate() {
            let idx = start + k as isize;
            *s = if idx >= 0 && (idx as usize) < samples.len() { samples[idx as usize] } else { 0.0 };
            e += *s * *s;
        }
        rms[i] = (e / win as f32).sqrt();
        if rms[i] < 1e-4 {
            continue;
        }
        // 声の山 (フォルマント) を線形予測 (LPC) で求める。
        // 高い音ほど弱くなる傾きを、先に持ち上げて (プリエンファシス) から窓を掛ける
        let mut x = vec![0.0f32; win];
        for k in 0..win {
            let prev = if k > 0 { seg[k - 1] } else { 0.0 };
            x[k] = (seg[k] - 0.97 * prev) * hann[k];
        }
        let a = lpc(&x, lpc_order);
        // 予測の係数の周波数特性 1 / |A|^2 が、声道の山の形 (包絡) になる
        for k in 0..win {
            buf[k] = Complex::new(if k < a.len() { a[k] } else { 0.0 }, 0.0);
        }
        fft.process(&mut buf);
        let half = win / 2;
        let env: Vec<f32> = buf[..half].iter().map(|c| 1.0 / c.norm_sqr().max(1e-12)).collect();
        let (f1, f2) = formants(&env, bin_hz);
        // 5 母音への近さ。一番近い母音を基準にするので、どれからも遠いときも一番近いものが選ばれる
        let d2: Vec<f32> = VOWELS.iter().map(|(p1, p2)| ((f1 - p1) / 150.0).powi(2) + ((f2 - p2) / 350.0).powi(2)).collect();
        let dmin = d2.iter().fold(f32::MAX, |m, v| m.min(*v));
        let mut w = [0.0f32; 5];
        let mut sum = 0.0;
        for k in 0..5 {
            w[k] = (-(d2[k] - dmin)).exp();
            sum += w[k];
        }
        for v in w.iter_mut() {
            *v /= sum;
        }
        vowel[i] = w;
        pitch[i] = estimate_pitch(&seg, sr);
    }

    // 口の開き: 大きい音 (95 パーセンタイル) を 1 に、小さい音は閉じる
    let mut sorted: Vec<f32> = rms.iter().copied().filter(|v| *v > 1e-4).collect();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let pct = |p: f32| -> f32 {
        if sorted.is_empty() {
            0.0
        } else {
            sorted[((sorted.len() - 1) as f32 * p) as usize]
        }
    };
    let loud = pct(0.95).max(1e-3);
    // 雑音の高さ: 一番静かなところの少し上。ただし、ずっと声が続くファイルでも小さい声を消さないよう、上限を付ける
    let floor = (pct(0.05) * 1.5).min(loud * 0.08).max(loud * 0.03);
    let mut open: Vec<f32> = rms
        .iter()
        .map(|v| (((v - floor) / (loud - floor).max(1e-6)).clamp(0.0, 1.0)).powf(0.7))
        .collect();
    // 口は音より少し先に開く (2 フレーム ≒ 33 ms 前へずらす)
    let n = open.len();
    open.rotate_left(2.min(n));
    if n >= 2 {
        open[n - 2..].fill(0.0);
    }
    // 開くときは速く、閉じるときはやや遅く
    let mut prev = 0.0f32;
    for v in open.iter_mut() {
        let k = if *v > prev { 0.65 } else { 0.35 };
        prev += (*v - prev) * k;
        *v = prev;
    }
    // 母音は前後 1 フレームでならす
    let mut vsm = vowel.clone();
    for i in 0..nframes {
        let a = i.saturating_sub(1);
        let b = (i + 2).min(nframes);
        for k in 0..5 {
            vsm[i][k] = (a..b).map(|j| vowel[j][k]).sum::<f32>() / (b - a) as f32;
        }
    }

    let emo = estimate_emotion(&rms, &pitch, &open);
    let mut frames = Vec::with_capacity(nframes * STRIDE);
    for i in 0..nframes {
        frames.push(open[i]);
        frames.extend_from_slice(&vsm[i]);
        frames.extend_from_slice(&emo[i]);
    }
    Analysis { duration, frames }
}

/// 自己相関とレビンソン・ダービンで、線形予測の係数 a[0..=p] (a[0] = 1) を求める
fn lpc(x: &[f32], p: usize) -> Vec<f32> {
    let mut r = vec![0.0f64; p + 1];
    for (k, rk) in r.iter_mut().enumerate() {
        *rk = (0..x.len() - k).map(|n| x[n] as f64 * x[n + k] as f64).sum();
    }
    let mut a = vec![0.0f64; p + 1];
    a[0] = 1.0;
    if r[0] <= 0.0 {
        return a.iter().map(|v| *v as f32).collect();
    }
    r[0] *= 1.0001; // わずかに白色雑音を足して安定させる
    let mut err = r[0];
    for i in 1..=p {
        let acc: f64 = r[i] + (1..i).map(|j| a[j] * r[i - j]).sum::<f64>();
        let k = -acc / err;
        let prev = a.clone();
        for j in 1..i {
            a[j] = prev[j] + k * prev[i - j];
        }
        a[i] = k;
        err *= 1.0 - k * k;
        if err <= 0.0 {
            break;
        }
    }
    a.iter().map(|v| *v as f32).collect()
}

/// 包絡の山から F1 / F2 [Hz] を選ぶ。
/// F1 と F2 が近くて 1 つの山に重なったとき (お・う) は、F2 を F1 のすぐ上とする
fn formants(env: &[f32], bin_hz: f32) -> (f32, f32) {
    // (周波数, 強さ) の山の並び
    let mut peaks: Vec<(f32, f32)> = Vec::new();
    for k in 1..env.len() - 1 {
        let f = k as f32 * bin_hz;
        if !(200.0..=3200.0).contains(&f) {
            continue;
        }
        if env[k] > env[k - 1] && env[k] >= env[k + 1] {
            // 山の頂を前後の値で補間して、ビンより細かく求める
            let (l, c, r) = (env[k - 1].ln(), env[k].ln(), env[k + 1].ln());
            let d = l - 2.0 * c + r;
            let off = if d.abs() > 1e-9 { 0.5 * (l - r) / d } else { 0.0 };
            peaks.push(((k as f32 + off.clamp(-0.5, 0.5)) * bin_hz, env[k]));
        }
    }
    // 声の高い人では倍音の間に偽の小さな山ができるので、範囲の中で一番強い山を取る
    let strongest = |lo: f32, hi: f32| -> Option<f32> {
        peaks.iter().filter(|(f, _)| *f > lo && *f <= hi).max_by(|a, b| a.1.partial_cmp(&b.1).unwrap()).map(|p| p.0)
    };
    // F1 は、高い音を持ち上げたぶん F2 より弱く見えることがある (お・う)。
    // 200〜1000 Hz で一番強い山の 3 割以上ある山のうち、一番低いものを取る
    let lowest_strong = |lo: f32, hi: f32, ratio: f32| -> Option<f32> {
        let top = strongest(lo, hi)?;
        let top_v = peaks.iter().find(|p| p.0 == top).map(|p| p.1).unwrap_or(0.0);
        Some(peaks.iter().filter(|(f, v)| *f > lo && *f <= hi && *v >= top_v * ratio).map(|p| p.0).fold(top, f32::min))
    };
    let f1 = lowest_strong(200.0, 1000.0, 0.3).unwrap_or(500.0);
    // F2 も同じ考えで、F1 の上の強い山のうち低いもの (お・う の F2 は F1 のすぐ上)
    let f2 = lowest_strong(f1 + 200.0, 3000.0, F2_RATIO).unwrap_or(f1 + 350.0);
    (f1, f2)
}

/// 自己相関で声の高さ [Hz] を求める (80〜500 Hz)。声でなければ 0
fn estimate_pitch(seg: &[f32], sr: f32) -> f32 {
    let r0: f32 = seg.iter().map(|v| v * v).sum();
    if r0 < 1e-6 {
        return 0.0;
    }
    let lo = (sr / 500.0) as usize;
    let hi = ((sr / 80.0) as usize).min(seg.len() - 1);
    let rs: Vec<f32> = (lo..=hi)
        .map(|lag| {
            let mut r = 0.0;
            for k in 0..seg.len() - lag {
                r += seg[k] * seg[k + lag];
            }
            // 長い遅れほど重なりが減るので補う
            r / r0 * seg.len() as f32 / (seg.len() - lag) as f32
        })
        .collect();
    let top = rs.iter().fold(0.0f32, |m, v| m.max(*v));
    // 倍の周期 (1 オクターブ下) に取り違えないよう、高い山の 85% を超える最初の山を取る
    let mut best = 0.0f32;
    let mut best_lag = 0usize;
    for i in 1..rs.len().saturating_sub(1) {
        if rs[i] >= top * 0.85 && rs[i] >= rs[i - 1] && rs[i] >= rs[i + 1] {
            best = rs[i];
            best_lag = lo + i;
            break;
        }
    }
    if best > 0.5 && best_lag > 0 { sr / best_lag as f32 } else { 0.0 }
}

/// 声の高さ・大きさ・抑揚から [happy, surprised, sad] を見積もる
fn estimate_emotion(rms: &[f32], pitch: &[f32], open: &[f32]) -> Vec<[f32; 3]> {
    let n = rms.len();
    let mut out = vec![[0.0f32; 3]; n];
    let voiced: Vec<bool> = (0..n).map(|i| pitch[i] > 0.0 && open[i] > 0.01).collect();
    let semi: Vec<f32> = pitch.iter().map(|p| if *p > 0.0 { 12.0 * (p / 100.0).log2() } else { 0.0 }).collect();
    let db: Vec<f32> = rms.iter().map(|r| 20.0 * r.max(1e-6).log10()).collect();
    let median = |v: Vec<f32>| -> Option<f32> {
        let mut v = v;
        if v.is_empty() {
            return None;
        }
        v.sort_by(|a, b| a.partial_cmp(b).unwrap());
        Some(v[v.len() / 2])
    };
    let (Some(p_med), Some(d_med)) = (
        median((0..n).filter(|i| voiced[*i]).map(|i| semi[i]).collect()),
        median((0..n).filter(|i| voiced[*i]).map(|i| db[i]).collect()),
    ) else {
        return out;
    };
    let half = (0.75 * FPS) as usize; // 前後 0.75 秒 = 1.5 秒の窓
    let mut surprise = 0.0f32;
    for i in 0..n {
        let a = i.saturating_sub(half);
        let b = (i + half + 1).min(n);
        let idx: Vec<usize> = (a..b).filter(|j| voiced[*j]).collect();
        // 窓の中で声が少なければ感情は乗せない
        let activity = idx.len() as f32 / (b - a) as f32;
        let mut e = [0.0f32; 3];
        if activity > 0.2 {
            let m = idx.len() as f32;
            let p = idx.iter().map(|j| semi[*j]).sum::<f32>() / m;
            let d = idx.iter().map(|j| db[*j]).sum::<f32>() / m;
            let var = (idx.iter().map(|j| (semi[*j] - p).powi(2)).sum::<f32>() / m).sqrt();
            let arousal = 0.5 * (p - p_med) / 4.0 + 0.5 * (d - d_med) / 6.0;
            let lively = (var - 2.5) / 3.0;
            // ふつうの話し方の揺れ (文の終わりで下がるなど) では出さないよう、小さな変化は無視する
            let dead = |v: f32| ((v - EMOTION_DEAD) / (1.0 - EMOTION_DEAD)).clamp(0.0, 1.0);
            e[0] = dead(arousal * 0.6 + lively * 0.4) * EMOTION_MAX;
            // 悲しみはふだんより低く小さいときだけ。抑揚が少ないと強める
            // 悲しみは、文の終わりで声が下がるだけでも出やすいので、幅を広めに取る
            let sad = (-arousal).max(0.0) * (1.0 + 0.5 * (-lively).clamp(0.0, 1.0)) * 0.8;
            e[2] = ((sad - 0.55) / 0.45).clamp(0.0, 1.0) * EMOTION_MAX;
            let fade = ((activity - 0.2) / 0.3).clamp(0.0, 1.0);
            e[0] *= fade;
            e[2] *= fade;
        }
        // 驚き: 直前 1 秒より急に大きく高くなったところ
        let s0 = i.saturating_sub(FPS as usize);
        let s1 = i.saturating_sub((0.2 * FPS) as usize);
        // 話し始め (無音の後) は比べない。直前 1 秒も話していて、その声より急に大きく高くなったときだけ
        if voiced[i] && s1 > s0 {
            let prev: Vec<usize> = (s0..s1).filter(|j| voiced[*j]).collect();
            if prev.len() as f32 >= (s1 - s0) as f32 * 0.5 {
                let before = prev.iter().map(|j| db[*j]).sum::<f32>() / prev.len() as f32;
                let now = (s1..=i).map(|j| db[j]).sum::<f32>() / (i + 1 - s1) as f32;
                let jump = ((now - before - 6.0) / 6.0).clamp(0.0, 1.0);
                let high = ((semi[i] - p_med) / 4.0).clamp(0.0, 1.0);
                surprise = surprise.max(jump * high * EMOTION_MAX);
            }
        }
        e[1] = surprise;
        surprise *= 0.97; // 約 0.5 秒で半分に
        out[i] = e;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const SR: u32 = 11025;

    /// 声の高さ f0 の倍音に、F1 / F2 の山を付けた母音らしい音
    fn vowel_tone(f0: f32, f1: f32, f2: f32, amp: f32, sec: f32) -> Vec<f32> {
        let n = (sec * SR as f32) as usize;
        let mut out = vec![0.0f32; n];
        let mut h = 1;
        while f0 * h as f32 <= 3500.0 {
            let f = f0 * h as f32;
            let g = (-((f - f1) / 90.0).powi(2)).exp() + 0.6 * (-((f - f2) / 110.0).powi(2)).exp() + 0.02;
            for (i, s) in out.iter_mut().enumerate() {
                *s += g * (std::f32::consts::TAU * f * i as f32 / SR as f32).sin();
            }
            h += 1;
        }
        let peak = out.iter().fold(0.0f32, |m, v| m.max(v.abs())).max(1e-6);
        out.iter_mut().for_each(|v| *v *= amp / peak);
        out
    }

    fn argmax(v: &[f32]) -> usize {
        (0..v.len()).max_by(|a, b| v[*a].partial_cmp(&v[*b]).unwrap()).unwrap()
    }

    #[test]
    fn silence_keeps_mouth_closed() {
        let a = analyze_samples(&vec![0.0; SR as usize], SR);
        assert!((0..a.frame_count()).all(|i| a.frame(i)[0] < 0.01));
    }

    #[test]
    fn opens_on_voice_and_closes_on_silence() {
        let mut s = vowel_tone(150.0, 750.0, 1250.0, 0.5, 1.0);
        s.extend(vec![0.0; SR as usize]);
        let a = analyze_samples(&s, SR);
        assert!(a.frame(30)[0] > 0.6, "声の間は開く: {}", a.frame(30)[0]);
        assert!(a.frame(100)[0] < 0.05, "無音で閉じる: {}", a.frame(100)[0]);
    }

    #[test]
    fn recognizes_five_vowels() {
        let names = ["aa", "ih", "ou", "ee", "oh"];
        for (k, (f1, f2)) in VOWELS.iter().enumerate() {
            // 声の高さ 220 Hz 以上の合成音では、倍音が少なく「お」が「あ」寄りになることがある (実際の声では読めている)
            for f0 in [120.0, 180.0] {
                let a = analyze_samples(&vowel_tone(f0, *f1, *f2, 0.5, 0.6), SR);
                let v = &a.frame(18)[1..6];
                assert_eq!(argmax(v), k, "{} (f0 {f0}) を当てる: {v:?}", names[k]);
            }
        }
    }

    #[test]
    fn excited_part_is_happy_and_quiet_part_is_sad() {
        // ふだんの声 4 秒 → 元気な声 2 秒 → ふだん 4 秒 → 静かで低い声 2 秒 → ふだん 2 秒
        let mut s = vowel_tone(160.0, 750.0, 1250.0, 0.35, 4.0);
        s.extend(vowel_tone(300.0, 750.0, 1250.0, 0.9, 2.0));
        s.extend(vowel_tone(160.0, 750.0, 1250.0, 0.35, 4.0));
        s.extend(vowel_tone(110.0, 750.0, 1250.0, 0.12, 2.0));
        s.extend(vowel_tone(160.0, 750.0, 1250.0, 0.35, 2.0));
        let a = analyze_samples(&s, SR);
        let normal = a.frame(120);
        let excited = a.frame(300);
        let quiet = a.frame(660);
        assert!(normal[6] < 0.05 && normal[8] < 0.05, "ふだんは感情なし: {:?}", &normal[6..]);
        assert!(excited[6] > 0.2, "元気な所は happy: {:?}", &excited[6..]);
        assert!(quiet[8] > 0.2, "静かな所は sad: {:?}", &quiet[6..]);
        // 急に大きく高くなった所で surprised
        let peak_surprise = (240..300).map(|i| a.frame(i)[7]).fold(0.0f32, f32::max);
        assert!(peak_surprise > 0.1, "驚き: {peak_surprise}");
    }

    #[test]
    fn decodes_wav_file() {
        let dir = std::env::temp_dir().join(format!("utsushi_lipsync_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("t.wav");
        let s = vowel_tone(150.0, 300.0, 2250.0, 0.5, 0.5);
        let rate = 44100u32;
        // 44.1 kHz の 16 bit ステレオで書く (間引きと、左右を混ぜるのも通す)
        let mut data = Vec::new();
        for v in &s {
            let x = (v * 32767.0) as i16;
            for _ in 0..4 {
                data.extend_from_slice(&x.to_le_bytes());
                data.extend_from_slice(&x.to_le_bytes());
            }
        }
        let mut f = Vec::new();
        f.extend_from_slice(b"RIFF");
        f.extend_from_slice(&(36 + data.len() as u32).to_le_bytes());
        f.extend_from_slice(b"WAVEfmt ");
        f.extend_from_slice(&16u32.to_le_bytes());
        f.extend_from_slice(&1u16.to_le_bytes());
        f.extend_from_slice(&2u16.to_le_bytes());
        f.extend_from_slice(&rate.to_le_bytes());
        f.extend_from_slice(&(rate * 4).to_le_bytes());
        f.extend_from_slice(&4u16.to_le_bytes());
        f.extend_from_slice(&16u16.to_le_bytes());
        f.extend_from_slice(b"data");
        f.extend_from_slice(&(data.len() as u32).to_le_bytes());
        f.extend_from_slice(&data);
        std::fs::write(&path, f).unwrap();
        let d = decode_file(path.to_str().unwrap(), true).unwrap();
        assert_eq!(d.rate, 11025);
        assert!((d.mono.len() as i64 - s.len() as i64).abs() < 10);
        // 再生用の音は元の 44.1 kHz ステレオのまま
        let pcm = d.pcm.unwrap();
        assert_eq!((pcm.rate, pcm.channels), (44100, 2));
        assert_eq!(pcm.samples.len(), s.len() * 4 * 2);
        let a = analyze_file(path.to_str().unwrap()).unwrap();
        assert!((a.duration - 0.5).abs() < 0.01);
        assert_eq!(argmax(&a.frame(15)[1..6]), 1, "い を当てる");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_file_is_an_error() {
        assert!(analyze_file("Z:/nope/none.mp3").is_err());
    }

    /// 手で確かめる用: LIPSYNC_DUMP=<ファイル> cargo test -p vrm-gdext --release dump_file -- --ignored --nocapture
    #[test]
    #[ignore]
    fn dump_file() {
        let Ok(path) = std::env::var("LIPSYNC_DUMP") else { return };
        let t0 = std::time::Instant::now();
        let a = analyze_file(&path).unwrap();
        println!("{path}: {:.2} 秒、解析 {} ms", a.duration, t0.elapsed().as_millis());
        let names = ["あ", "い", "う", "え", "お"];
        let mut i = 0;
        while i < a.frame_count() {
            let f = a.frame(i);
            let bar = "#".repeat((f[0] * 20.0) as usize);
            println!("{:5.2}s {:<20} {} happy {:.2} surprised {:.2} sad {:.2}", i as f32 / FPS, bar, names[argmax(&f[1..6])], f[6], f[7], f[8]);
            i += 6;
        }
    }
}
