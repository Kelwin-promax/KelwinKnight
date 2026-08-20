extends SceneTree

## Prepara folhas de sprite: tira o fundo, acha cada boneco e grava as medidas.
##
## Duas decisoes valem explicacao.
##
## 1. O fundo sai por INUNDACAO a partir das bordas, nao por "toda cor parecida
##    com o fundo vira transparente". A camisa do jogador e um cinza escuro a
##    distancia 27 do verde do fundo, dentro de qualquer tolerancia util - um
##    filtro global comeria o tronco. A inundacao so alcanca o que esta ligado
##    a borda, entao o interior do corpo esta a salvo por construcao.
##
## 2. As celulas NAO formam uma grade regular. Estas folhas sao desenhadas, nao
##    geradas por ferramenta de tileset: o salto do dash, por exemplo, atravessa
##    a fronteira de duas celulas de 200px. Fatiar em 4x5 fixo cortaria o boneco
##    ao meio. Entao cada figura e achada pela propria silhueta, por projecao de
##    linhas e colunas, e o resultado sai num .json que o jogo le.
##
## Roda offline, uma vez por folha nova:
##   godot --headless --path . --script res://scripts/tools/preparar_folha.gd

const PASTA := "res://assets/sprites"

## Distancia maxima por canal ate a cor do fundo para a inundacao seguir.
## O JPEG suja o fundo chapado, entao exigir igualdade exata nao funciona.
const TOL := 38
## Bandas/figuras menores que isto sao ruido de compressao, nao boneco.
const MIN_ALTURA_BANDA := 24
const MIN_LARGURA_FIG := 16
## Fatia de baixo da figura usada para achar o centro dos pes.
const FAIXA_PES := 0.12

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var alvos: Array[String] = []
	for a in args:
		if not a.begins_with("--"):
			alvos.append(a)
	if alvos.is_empty():
		var dir := DirAccess.open(PASTA)
		if dir != null:
			dir.list_dir_begin()
			var n := dir.get_next()
			while n != "":
				if n.to_lower().ends_with(".jpg") or n.to_lower().ends_with(".jpeg"):
					alvos.append(n.get_basename())
				n = dir.get_next()
	for nome in alvos:
		_preparar(nome)
	quit()

func _preparar(nome: String) -> void:
	print("\n================  ", nome, "  ================")
	var f := FileAccess.open("%s/%s.jpg" % [PASTA, nome], FileAccess.READ)
	if f == null:
		print("ERRO: nao consegui ler a folha")
		return
	var bytes := f.get_buffer(f.get_length())
	f.close()

	var img := Image.new()
	if img.load_jpg_from_buffer(bytes) != OK:
		print("ERRO: o arquivo nao decodificou como JPEG")
		return
	img.convert(Image.FORMAT_RGBA8)

	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	print("folha: %d x %d" % [w, h])

	_remover_fundo(d, w, h)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, d)

	var base := nome.to_lower()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [PASTA, base]))

	# versao de conferencia: o que foi removido aparece em magenta
	var dbg := d.duplicate()
	var i := 0
	while i < dbg.size():
		if dbg[i + 3] == 0:
			dbg[i] = 255
			dbg[i + 1] = 0
			dbg[i + 2] = 255
			dbg[i + 3] = 255
		i += 4
	var img_dbg := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, dbg)
	img_dbg.save_png(ProjectSettings.globalize_path("%s/_conferir_%s.png" % [PASTA, base]))

	# ------------------------------------------------------- achar os bonecos
	var bandas := _bandas(d, w, h)
	var saida := {"textura": "%s/%s.png" % [PASTA, base], "bandas": []}
	var altura_ref := 0

	for bi in range(bandas.size()):
		var b: Vector2i = bandas[bi]
		var figs := _figuras(d, w, b.x, b.y)
		var lista := []
		var desc := PackedStringArray()
		for fg in figs:
			var r: Rect2i = fg
			altura_ref = maxi(altura_ref, r.size.y)
			var ax := _centro_dos_pes(d, w, r)
			lista.append({"x": r.position.x, "y": r.position.y,
					"w": r.size.x, "h": r.size.y, "ax": ax})
			desc.append("%dx%d" % [r.size.x, r.size.y])
		saida["bandas"].append(lista)
		print("  banda %d (y %d..%d): %d figuras  [%s]" % [bi, b.x, b.y,
				figs.size(), ", ".join(desc)])

	saida["altura_ref"] = altura_ref
	print("  altura de referencia (boneco mais alto): %d px" % altura_ref)

	var jf := FileAccess.open("%s/%s.json" % [PASTA, base], FileAccess.WRITE)
	jf.store_string(JSON.stringify(saida, "\t"))
	jf.close()
	print("  gravado: %s.png + %s.json  (confira _conferir_%s.png)" % [base, base, base])

# ------------------------------------------------------------------ inundacao
func _remover_fundo(d: PackedByteArray, w: int, h: int) -> void:
	var fr := int(d[0])
	var fg := int(d[1])
	var fb := int(d[2])
	print("cor do fundo (canto): rgb(%d, %d, %d)" % [fr, fg, fb])
	var visto := PackedByteArray()
	visto.resize(w * h)
	var fila := PackedInt32Array()

	for x in range(w):
		_semear(d, visto, fila, x, 0, w, fr, fg, fb)
		_semear(d, visto, fila, x, h - 1, w, fr, fg, fb)
	for y in range(h):
		_semear(d, visto, fila, 0, y, w, fr, fg, fb)
		_semear(d, visto, fila, w - 1, y, w, fr, fg, fb)

	var qi := 0
	while qi < fila.size():
		var idx := fila[qi]
		qi += 1
		var x := idx % w
		var y := idx / w
		if x > 0:
			_semear(d, visto, fila, x - 1, y, w, fr, fg, fb)
		if x < w - 1:
			_semear(d, visto, fila, x + 1, y, w, fr, fg, fb)
		if y > 0:
			_semear(d, visto, fila, x, y - 1, w, fr, fg, fb)
		if y < h - 1:
			_semear(d, visto, fila, x, y + 1, w, fr, fg, fb)

	for j in range(w * h):
		if visto[j] == 1:
			d[j * 4 + 3] = 0
	print("fundo removido: %.1f%%" % (100.0 * float(fila.size()) / float(w * h)))

func _semear(d: PackedByteArray, visto: PackedByteArray, fila: PackedInt32Array,
		x: int, y: int, w: int, fr: int, fg: int, fb: int) -> void:
	var i := y * w + x
	if visto[i] == 1:
		return
	var b := i * 4
	if absi(int(d[b]) - fr) > TOL or absi(int(d[b + 1]) - fg) > TOL \
			or absi(int(d[b + 2]) - fb) > TOL:
		return
	visto[i] = 1
	fila.append(i)

# ----------------------------------------------------------------- deteccao
## Faixas horizontais com pixel opaco, separadas por vao vazio.
func _bandas(d: PackedByteArray, w: int, h: int) -> Array:
	var out := []
	var ini := -1
	for y in range(h):
		var tem := false
		for x in range(w):
			if d[(y * w + x) * 4 + 3] > 8:
				tem = true
				break
		if tem and ini < 0:
			ini = y
		elif not tem and ini >= 0:
			if y - ini >= MIN_ALTURA_BANDA:
				out.append(Vector2i(ini, y - 1))
			ini = -1
	if ini >= 0 and h - ini >= MIN_ALTURA_BANDA:
		out.append(Vector2i(ini, h - 1))
	return out

## Dentro de uma banda, cada boneco e um grupo de colunas com pixel opaco.
func _figuras(d: PackedByteArray, w: int, y0: int, y1: int) -> Array:
	var out := []
	var ini := -1
	for x in range(w):
		var tem := false
		for y in range(y0, y1 + 1):
			if d[(y * w + x) * 4 + 3] > 8:
				tem = true
				break
		if tem and ini < 0:
			ini = x
		elif not tem and ini >= 0:
			if x - ini >= MIN_LARGURA_FIG:
				out.append(_apertar(d, w, ini, x - 1, y0, y1))
			ini = -1
	if ini >= 0 and w - ini >= MIN_LARGURA_FIG:
		out.append(_apertar(d, w, ini, w - 1, y0, y1))
	return out

func _apertar(d: PackedByteArray, w: int, x0: int, x1: int, y0: int, y1: int) -> Rect2i:
	var miny := y1
	var maxy := y0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if d[(y * w + x) * 4 + 3] > 8:
				if y < miny:
					miny = y
				if y > maxy:
					maxy = y
				break
	return Rect2i(x0, miny, x1 - x0 + 1, maxy - miny + 1)

## Centro horizontal dos pes. Ancorar pelo centro da caixa faria o corpo
## deslizar quando o braco estica num soco; o pe fica parado.
func _centro_dos_pes(d: PackedByteArray, w: int, r: Rect2i) -> int:
	var alt := maxi(1, int(float(r.size.y) * FAIXA_PES))
	var y0 := r.position.y + r.size.y - alt
	var minx := r.position.x + r.size.x
	var maxx := r.position.x
	for y in range(y0, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if d[(y * w + x) * 4 + 3] > 8:
				if x < minx:
					minx = x
				if x > maxx:
					maxx = x
	if maxx < minx:
		return r.size.x / 2
	return (minx + maxx) / 2 - r.position.x
