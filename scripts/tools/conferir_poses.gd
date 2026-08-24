extends Node2D

## Folha de conferencia: desenha TODA pose que o jogo sabe usar, quadro a
## quadro, com o nome da acao embaixo. E o jeito de ver se o mapa de
## animacoes bate com a folha sem ter que caçar o momento certo no playtest.
##
##   godot --path . res://scenes/Poses.tscn -- --saida=C:/algum/lugar

const COL := 128.0
const LIN := 168.0
const POR_LINHA := 7

var _fonte: Font
var _saida := ""

func _ready() -> void:
	_fonte = ThemeDB.fallback_font
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--saida="):
			_saida = a.substr(8)
	if not SpriteJogador.disponivel():
		push_error("folha do jogador nao carregou")
	await RenderingServer.frame_post_draw
	await get_tree().create_timer(0.3).timeout
	if _saida != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(_saida + "/poses.png")
		print("[poses] gravado ", _saida, "/poses.png")
	get_tree().quit()

func _draw() -> void:
	var tela := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, tela), Color(0.10, 0.09, 0.10))

	# A folha cresceu de 22 para ~37 quadros e passou a nao caber em 7 colunas:
	# as ultimas linhas ficavam fora da tela e a conferencia mentia por omissao.
	# Aperta a grade ate caber, em vez de cortar em silencio.
	var total := 0
	for nome_c in SpriteJogador.ANIMS:
		total += (SpriteJogador.ANIMS[nome_c]["figs"] as Array).size()
	var por_linha := POR_LINHA
	while por_linha < total and \
			130.0 + ceil(float(total) / float(por_linha)) * LIN > tela.y:
		por_linha += 1
	var col := minf(COL, (tela.x - 40.0) / float(por_linha))

	var i := 0
	for nome in SpriteJogador.ANIMS:
		var d: Dictionary = SpriteJogador.ANIMS[nome]
		var figs: Array = d["figs"]
		var fps := float(d["fps"])
		for q in range(figs.size()):
			var pos := Vector2(30.0 + (float(i % por_linha) + 0.5) * col,
					130.0 + float(i / por_linha) * LIN)

			# chao de referencia: mostra se o pe esta ancorado certo
			draw_line(pos - Vector2(46, 0), pos + Vector2(46, 0),
					Color(1, 1, 1, 0.16), 1.0)

			var t := 0.0
			var prog := 0.0
			if fps > 0.0:
				t = float(q) / fps
			elif figs.size() > 1:
				prog = (float(q) + 0.5) / float(figs.size())
			# a posicao vai pelo parametro: desenhar() define o proprio
			# transform e engoliria um draw_set_transform daqui.
			SpriteJogador.desenhar(self, String(nome), t, prog, 1.0, 0.0, pos)

			var rot := "%s %d/%d" % [nome, q + 1, figs.size()] if figs.size() > 1 else String(nome)
			draw_string(_fonte, pos + Vector2(-col * 0.5 + 2.0, 22), rot,
					HORIZONTAL_ALIGNMENT_LEFT, col - 4.0, 11, Color(0.86, 0.84, 0.80))
			i += 1
