extends SceneTree

const Vrm0MigratorScript := preload("res://scripts/vrm/vrm0_migrator.gd")

func _initialize() -> void:
	var sample0 := {
		"nodes": [
			{"name": "Root", "children": [1, 2]},
			{"name": "hips", "children": [3]},
			{"name": "FaceMesh", "mesh": 0},
			{"name": "hair0", "children": [4]},
			{"name": "hair1", "children": []},
		],
		"materials": [
			{"name": "Skin", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1]}}
		],
		"extensions": {
			"VRM": {
				"meta": {"title": "LegacyChar", "author": "Tester", "allowedUserName": "Everyone"},
				"humanoid": {"humanBones": [{"bone": "hips", "node": 1}]},
				"blendShapeMaster": {
					"blendShapeGroups": [
						{
							"name": "Joy",
							"presetName": "joy",
							"binds": [{"mesh": 0, "index": 2, "weight": 85}],
							"materialValues": [
								{"materialName": "Skin", "propertyName": "_ShadeColor", "targetValue": [0.8, 0.5, 0.5, 1.0]}
							]
						},
						{"name": "wink_custom", "presetName": "unknown", "binds": [{"mesh": 0, "index": 1, "weight": 100}]}
					]
				},
				"firstPerson": {
					"lookAtTypeName": "Bone",
					"meshAnnotations": [{"mesh": 0, "firstPersonFlag": "ThirdPersonOnly"}]
				},
				"secondaryAnimation": {
					"colliderGroups": [{"node": 1, "colliders": [{"offset": {"x": 0, "y": 0, "z": 0}, "radius": 0.1}]}],
					"boneGroups": [{"comment": "Hair", "stiffiness": 1.2, "gravityPower": 0.2, "dragForce": 0.5, "hitRadius": 0.02, "bones": [3], "colliderGroups": [1]}]
				},
				"materialProperties": [
					{"shader": "VRM/MToon", "renderQueue": 2000, "floatProperties": {"_ShadeToony": 0.85, "_OutlineWidthMode": 1, "_OutlineWidth": 0.2}, "vectorProperties": {"_ShadeColor": [0.9, 0.7, 0.7, 1.0]}}
				]
			}
		}
	}

	var migrated: Dictionary = Vrm0MigratorScript.migrate_vrm0_to_vrm1(sample0)
	var vrm1: Dictionary = migrated["extensions"]["VRMC_vrm"]
	var sb1: Dictionary = migrated["extensions"]["VRMC_springBone"]
	var mtoon1: Dictionary = migrated["materials"][0]["extensions"]["VRMC_materials_mtoon"]

	var ok: bool = (
		vrm1["meta"]["name"] == "LegacyChar"
		and vrm1["humanoid"]["humanBones"]["hips"]["node"] == 1
		and vrm1["expressions"]["preset"].has("happy")
		and is_equal_approx(vrm1["expressions"]["preset"]["happy"]["morphTargetBinds"][0]["weight"], 0.85)
		and vrm1["expressions"]["custom"].has("wink_custom")
		and vrm1["firstPerson"]["meshAnnotations"][0]["type"] == "thirdPersonOnly"
		and sb1["springs"].size() == 1
		and mtoon1["outlineWidthMode"] == "worldCoordinates"
	)
	print("TEST_VRM0_MIGRATOR_RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
