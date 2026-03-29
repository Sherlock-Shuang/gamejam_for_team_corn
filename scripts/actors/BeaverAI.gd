# BeaverAI.gd (河狸专属 AI)
extends EnemyBase

func _ready() -> void:
	super._ready()
	attack_cooldown = 0.8

func _custom_behavior(delta: float) -> void:
	if is_attacking:
		if anim.animation != "attack" and anim.sprite_frames.has_animation("attack"):
			anim.play("attack")
	else:
		if anim.animation != "walk" and anim.sprite_frames.has_animation("walk"):
			anim.play("walk")
