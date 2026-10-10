extends "res://tests/m6s_real_combat_damage_window_smoke.gd"
## The legacy synthetic fixture put ReceiveArea at the feet (y=-19) and
## demanded hits at an arbitrary 50px root gap without setting a combat pose.
## Run the production Raider/Boss Window damage, timing and miss gate instead.
## M6R separately retains exact hand/Shape, small-radius and duplicate-hit checks.