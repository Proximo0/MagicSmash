# SkelForm .skf (v0.9) as far as the public spec states it (fetched 22 Nov 2026 from skelform.org/dev-docs/v0.9/file-specs.html)
A .skf is a zip: armature.json, atlas0.png (atlasN numbered from 0), optional editor.json, thumbnail.png, readme.md.
armature.json top level: version (String), baked_ik (Bool,false), img_format ("PNG"), clear_color, and arrays bones,
animations, atlases, styles, inverse_kinematics, visuals, physics (default []).
bones[]: id (uint), name, pos (Vec2), rot (Float; UNITS NOT STATED), scale (Vec2,(1,1)), parent_id (Int,-1), tex
(String: a texture name in a style), zindex (Int), hidden (Bool), tint (Color, white 255,255,255,255),
inverse_kinematics_id/visuals_id/physics_id (Int,-1).
atlases[]: filename, size (Vec2 px). styles[]: id, name, textures[]: name, offset (Vec2 top-left px in atlas), size
(Vec2 px), atlas_idx.
animations[]: id (String), name, fps (uint), keyframes[]: frame (uint), bone_name (String), element (String; only
"PosX" is shown; others unknown, likely PosY, Rot, ScaleX, ScaleY), value (Float), next_kf (Int,-1), start_handle
(0.333), end_handle (0.666).
inverse_kinematics[]: family_id, constraint ("None"|"Clockwise"|"CounterClockwise"), mode ("FABRIK"|"Arc"),
target_id, bone_ids[], mimic_target.
NOT STATED: rot units, y axis direction, whether Vec2 is [x,y] or {x,y}, the version string, element names. So a file
we write is UNVERIFIED until it has been opened once in the editor (v0.9) on a PC and one exported file compared.
Keep the writer in one small module with these unknowns as named constants at the top so they can be flipped.
