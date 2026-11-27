//! FFmpeg の場所を決める。録画・リップシンクの音の重ね書き・音声の読み込みで共通に使う。
//!
//! 探す順番:
//! 1. 環境変数 `VRMVIEWER_FFMPEG` (ffmpeg.exe のパス。テストや特別な環境向け)
//! 2. アプリのフォルダの `tools\ffmpeg\bin\ffmpeg.exe` (設定画面のボタンで入れたもの)
//! 3. PATH の上の ffmpeg
//!
//! アプリのフォルダは Godot 側が知っているので、起動時に [`set_app_dir`] で教えてもらう。

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::RwLock;

static APP_DIR: RwLock<Option<PathBuf>> = RwLock::new(None);

#[cfg(windows)]
const EXE: &str = "ffmpeg.exe";
#[cfg(not(windows))]
const EXE: &str = "ffmpeg";

/// アプリが入れる FFmpeg の置き場所 (アプリのフォルダからの相対パス)
pub const APP_SUBDIR: &str = "tools/ffmpeg";

pub fn set_app_dir(dir: &str) {
    let d = dir.trim();
    if let Ok(mut g) = APP_DIR.write() {
        *g = if d.is_empty() { None } else { Some(PathBuf::from(d)) };
    }
}

/// アプリのフォルダに入れた ffmpeg のパス (無くても返す)
pub fn app_local_path() -> Option<PathBuf> {
    let g = APP_DIR.read().ok()?;
    g.as_ref().map(|d| d.join(APP_SUBDIR).join("bin").join(EXE))
}

/// 見つかった ffmpeg と、どこで見つけたか ("env" / "app" / "path")
pub fn resolve() -> Option<(PathBuf, &'static str)> {
    if let Ok(p) = std::env::var("VRMVIEWER_FFMPEG") {
        let p = PathBuf::from(p.trim());
        if p.is_file() {
            return Some((p, "env"));
        }
    }
    if let Some(p) = app_local_path() {
        if p.is_file() {
            return Some((p, "app"));
        }
    }
    find_on_path().map(|p| (p, "path"))
}

fn find_on_path() -> Option<PathBuf> {
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|d| d.join(EXE))
        .find(|p| is_runnable(p))
}

fn is_runnable(p: &Path) -> bool {
    // winget の Links のようなシンボリックリンクも、たどった先がファイルなら使える
    std::fs::metadata(p).map(|m| m.is_file()).unwrap_or(false)
}

/// ffmpeg を起動する Command。見つからなければ "ffmpeg" のまま (起動に失敗して、呼び出し元が案内を出す)
pub fn command() -> Command {
    let exe = resolve().map(|(p, _)| p).unwrap_or_else(|| PathBuf::from("ffmpeg"));
    Command::new(exe)
}

/// 起動に失敗したときの文言 (見つからないときは、入れ方を案内する)
pub fn spawn_error(e: &std::io::Error) -> String {
    if e.kind() == std::io::ErrorKind::NotFound {
        "FFmpeg が見つかりません。設定画面の「出力」ページの「FFmpeg を入れる」から入れてください".to_string()
    } else {
        format!("FFmpeg を起動できません: {e}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_local_path_follows_app_dir() {
        set_app_dir("C:/Apps/UtsushiMirror");
        let p = app_local_path().unwrap();
        assert!(p.ends_with(Path::new("tools/ffmpeg/bin").join(EXE)));
        set_app_dir("");
        assert!(app_local_path().is_none());
    }
}
