extends SceneTree

## Testes das regras do GDD. Rodam sem janela e sem cena:
##   godot --headless --path . --script res://tests/test_rules.gd
## Tudo que esta aqui e funcao pura de Balance, entao um numero que sair do
## documento quebra o teste em vez de virar bug de gameplay silencioso.

var _ok := 0
var _falhas: Array[String] = []

func _initialize() -> void:
	print("")
	_secao("7.3 - parry e a tabela de resistencia")
	_teste_parry()
	_secao("3.2 - curva de adaptacao por consumo")
	_teste_consumo()
	_secao("7.6 - proficiencia por uso")
	_teste_proficiencia()
	_secao("7.5 - combo e especializacao")
	_teste_combo()
	_secao("2 - spawn, teto e gatilho do mini-boss")
	_teste_spawn()
	_secao("4 e 5 - bestiario e cavaleiros")
	_teste_tabelas()
	_secao("7.7 - cone de visao")
	_teste_cone()
	_relatorio()

# ---------------------------------------------------------------- 7.3 parry
func _teste_parry() -> void:
	# A tabela do documento, faixa por faixa, contra um golpe de 40.
	var r100 := Balance.parry_result(100, 40.0)
	_afirma(is_equal_approx(r100["dano"], 0.0), "resistencia 100+: parry perfeito nao machuca", "dano=%.1f" % r100["dano"])
	_afirma(r100["atordoa"] and r100["critico"], "resistencia 100+: atordoa e garante o critico")

	var r99 := Balance.parry_result(99, 40.0)
	_afirma(is_equal_approx(r99["dano"], 10.0), "75-99: recebe 25% do dano", "40 -> %.1f" % r99["dano"])
	_afirma(r99["atordoa"] and r99["critico"], "75-99: ainda atordoa e da critico")

	var r50 := Balance.parry_result(50, 40.0)
	_afirma(is_equal_approx(r50["dano"], 20.0), "50-74: recebe 50% do dano", "40 -> %.1f" % r50["dano"])

	var r25 := Balance.parry_result(25, 40.0)
	_afirma(is_equal_approx(r25["dano"], 30.0), "25-49: recebe 75% do dano", "40 -> %.1f" % r25["dano"])
	_afirma(is_equal_approx(r25["vulneravel"], 0.3), "25-49: fica vulneravel 0.3s")
	_afirma(r25["atordoa"], "25-49: ainda atordoa o inimigo")

	var r10 := Balance.parry_result(10, 40.0)
	_afirma(is_equal_approx(r10["dano"], 38.0), "1-24: recebe 95% do dano", "40 -> %.1f" % r10["dano"])
	_afirma(not r10["atordoa"], "1-24: NAO atordoa o inimigo")
	_afirma(is_equal_approx(r10["vulneravel"], 0.5), "1-24: vulneravel 0.5s")

	var r0 := Balance.parry_result(0, 40.0)
	_afirma(is_equal_approx(r0["dano"], 40.0), "resistencia 0: recebe o dano inteiro")
	_afirma(r0["queda"] and not r0["atordoa"], "resistencia 0: o jogador cai e nao atordoa")

	# A regra central do 7.3: parry so e limpo com resistencia 100+.
	var monotona := true
	var anterior := -1.0
	for res in range(120, -1, -1):
		var d := float(Balance.parry_result(res, 40.0)["dano"])
		if anterior >= 0.0 and d < anterior:
			monotona = false
		anterior = d
	_afirma(monotona, "quanto menor a resistencia, maior o dano do parry (sem inversao)")
	_afirma(Balance.PARRY_WINDOW == 0.2, "a janela de parry e de 0.2s")

# ------------------------------------------------------------- 3.2 consumo
func _teste_consumo() -> void:
	# Os limites de cada faixa da curva de 51.
	var c1 := Balance.consume_effect(0)     # 1o consumo
	_afirma(c1["desmaio"] and c1["vomito"], "1o consumo: vomito de sangue e desmaio")
	var c20 := Balance.consume_effect(19)   # 20o
	_afirma(c20["desmaio"], "20o consumo: ainda desmaia")
	var c21 := Balance.consume_effect(20)   # 21o
	_afirma(not c21["desmaio"] and c21["lentidao"] > 0.0, "21o consumo: para de desmaiar, fica lento")
	var c35 := Balance.consume_effect(34)
	_afirma(c35["lentidao"] > 0.0, "35o consumo: ainda com mobilidade reduzida")
	var c36 := Balance.consume_effect(35)
	_afirma(is_equal_approx(c36["lentidao"], 0.0) and int(c36["hp"]) > 0, "36o consumo: so perde HP")
	var c50 := Balance.consume_effect(49)
	_afirma(int(c50["hp"]) > 0, "50o consumo: ainda perde HP")
	var c51 := Balance.consume_effect(50)
	_afirma(int(c51["hp"]) == 0 and not c51["vomito"] and not c51["desmaio"],
			"51o consumo: nenhum efeito colateral", "faixa " + String(c51["faixa"]))

	# A gravidade nunca sobe ao longo da curva.
	var pior := 99
	var so_desce := true
	for i in range(0, 60):
		var hp := int(Balance.consume_effect(i)["hp"])
		if hp > pior:
			so_desce = false
		pior = hp
	_afirma(so_desce, "a gravidade do efeito so diminui com a adaptacao")

	# 3.3: a habilidade satura no 5o consumo da MESMA criatura.
	_afirma(is_equal_approx(Balance.habilidade_escala(1), 0.0), "1o consumo de uma criatura: habilidade no basico")
	_afirma(is_equal_approx(Balance.habilidade_escala(5), 1.0), "5o consumo da mesma criatura: efeito maximo / CD zero")
	_afirma(is_equal_approx(Balance.habilidade_escala(9), 1.0), "alem do 5o: satura, nao passa de 1.0")

# --------------------------------------------------------- 7.6 proficiencia
func _teste_proficiencia() -> void:
	_afirma(Balance.proficiency_level(0) == 1, "0 usos: nivel 1 Iniciante")
	_afirma(Balance.proficiency_level(4) == 1, "4 usos: ainda nivel 1")
	_afirma(Balance.proficiency_level(5) == 2, "5 usos: nivel 2 Aprendiz")
	_afirma(Balance.proficiency_level(15) == 3, "15 usos: nivel 3 Praticante")
	_afirma(Balance.proficiency_level(30) == 4, "30 usos: nivel 4 Veterano (habilidade especial)")
	_afirma(Balance.proficiency_level(50) == 5, "50 usos: nivel 5 Mestre")
	_afirma(Balance.proficiency_level(999) == 5, "o teto e o nivel 5")
	_afirma(Balance.proficiency_bonus(0) == 0, "bonus de dano no nivel 1: +0")
	_afirma(Balance.proficiency_bonus(5) == 1, "bonus no nivel 2: +1")
	_afirma(Balance.proficiency_bonus(15) == 2, "bonus no nivel 3: +2")
	_afirma(Balance.proficiency_bonus(30) == 3, "bonus no nivel 4: +3")
	_afirma(Balance.proficiency_bonus(50) == 5, "bonus no nivel 5: +5")

# ---------------------------------------------------------------- 7.5 combo
func _teste_combo() -> void:
	_afirma(is_equal_approx(Balance.damage_multiplier(0, 0), 1.0), "sem combo: dano base")
	_afirma(is_equal_approx(Balance.damage_multiplier(1, 0), 1.09), "1 acerto consecutivo: +9%")
	_afirma(is_equal_approx(Balance.damage_multiplier(3, 0), 1.27), "3 acertos consecutivos: +27%")
	_afirma(is_equal_approx(Balance.damage_multiplier(0, 15), 1.30), "especializacao satura em +30%",
			"15 repeticoes = +30%")
	_afirma(is_equal_approx(Balance.damage_multiplier(0, 99), 1.30), "especializacao nao passa de +30%")
	_afirma(Balance.COMBO_JANELA == 2.0, "o combo reseta apos 2s sem acertar")

	# 5: Impeto Belicoso, a arma de Guerra.
	_afirma(is_equal_approx(Balance.impeto_belicoso(1), 1.05), "Impeto Belicoso: +5% por acerto")
	_afirma(is_equal_approx(Balance.impeto_belicoso(10), 1.50), "Impeto Belicoso: teto de +50%")
	_afirma(is_equal_approx(Balance.impeto_belicoso(40), 1.50), "Impeto Belicoso: nao passa de +50%")

# ---------------------------------------------------------------- 2 spawn
func _teste_spawn() -> void:
	_afirma(Balance.SPAWN_INTERVALO == 10.0, "um monstro surge a cada 10s")
	_afirma(Balance.CAP_BASE == 30, "teto inicial de 30 monstros vivos")
	_afirma(Balance.monster_cap(0) == 30, "sem cavaleiro morto: teto 30")
	_afirma(Balance.monster_cap(1) == 31, "1 cavaleiro morto: teto 31")
	_afirma(Balance.monster_cap(2) == 33, "2 cavaleiros mortos: teto 33")
	_afirma(Balance.monster_cap(4) >= 39, "4+ cavaleiros: teto 39 ou mais", "= %d" % Balance.monster_cap(4))

	var cresce := true
	for i in range(0, 8):
		if Balance.monster_cap(i + 1) < Balance.monster_cap(i):
			cresce = false
	_afirma(cresce, "o teto nunca encolhe conforme os cavaleiros caem")
	_afirma(Balance.MINIBOSS_KILLS == 5 and Balance.MINIBOSS_JANELA == 60.0,
			"gatilho do mini-boss: 5 mortes em menos de 60s")
	_afirma(Balance.INSPECAO_JANELA == 30.0, "30s para inspecionar o corpo do cavaleiro")

# --------------------------------------------------------- 4 e 5 tabelas
func _teste_tabelas() -> void:
	_afirma(Balance.BESTIARIO.size() == 10, "os 10 inimigos comuns do bestiario",
			"= %d" % Balance.BESTIARIO.size())
	var hps := {"rastejador":25, "carniceiro":40, "peleveloz":20, "ambutcher":25, "vigia":45,
				"toxoplasma":30, "deslizador":22, "aterror":35, "regen":50, "furioso":60}
	var hp_ok := true
	var erro := ""
	for id in hps:
		var b := Balance.bestiario_por_id(String(id))
		if b.is_empty() or int(b["hp"]) != int(hps[id]):
			hp_ok = false
			erro = String(id)
	_afirma(hp_ok, "o HP de cada inimigo bate com a tabela do 4", erro)

	var ids := {}
	for b in Balance.BESTIARIO:
		ids[b["id"]] = true
	_afirma(ids.size() == 10, "nenhum id de criatura repetido")

	var habs := {}
	for b in Balance.BESTIARIO:
		habs[b["hab"]] = true
	_afirma(habs.size() == 10, "cada criatura concede uma habilidade distinta")

	_afirma(Balance.CAVALEIROS.size() == 5, "os 5 Cavaleiros do Apocalipse")
	var guerra := Balance.cavaleiro_por_indice(0)
	_afirma(String(guerra["nome"]) == "Guerra" and int(guerra["hp"]) == 120,
			"o 1o Cavaleiro e Guerra, com 120 HP")
	_afirma(String(guerra["arma"]) == "Espada Colossal", "Guerra larga a Espada Colossal")
	var hps_cav := [120, 100, 90, 85, 130]
	var cav_ok := true
	for i in range(5):
		if int(Balance.CAVALEIROS[i]["hp"]) != hps_cav[i]:
			cav_ok = false
	_afirma(cav_ok, "o HP dos 5 Cavaleiros bate com a tabela do 5")

# ----------------------------------------------------------------- 7.7 cone
func _teste_cone() -> void:
	var olho := Vector2.ZERO
	var mira := Vector2.RIGHT
	_afirma(Balance.dentro_do_cone(olho, mira, Vector2(100, 0)), "alvo bem na frente: dentro do cone")
	_afirma(not Balance.dentro_do_cone(olho, mira, Vector2(-100, 0)), "alvo atras: fora do cone (permite o furtivo)")
	_afirma(not Balance.dentro_do_cone(olho, mira, Vector2(0, 100)), "alvo a 90 graus: fora do cone de 55")
	_afirma(Balance.dentro_do_cone(olho, mira, Vector2(100, 60)), "alvo a ~31 graus: dentro do cone")
	_afirma(not Balance.dentro_do_cone(olho, mira, Vector2(400, 0)), "alvo longe demais: fora do alcance",
			"alcance %.0f" % Balance.CONE_ALCANCE)
	_afirma(Balance.ALERTA_ATRASO == 0.5, "0.5s de alerta antes de perseguir")
	_afirma(Balance.BUSCA_DURACAO == 5.0, "5s de busca antes de voltar ao passivo")
	_afirma(Balance.BACKSTAB_MULT == 2.0, "ataque pelas costas: critico garantido 2x")

# ------------------------------------------------------------------ apoio
func _secao(titulo: String) -> void:
	print("\n=== " + titulo + " ===")

func _afirma(cond: bool, desc: String, extra: String = "") -> void:
	var sufixo := ("  [" + extra + "]") if extra != "" else ""
	if cond:
		_ok += 1
		print("  ok  " + desc + sufixo)
	else:
		_falhas.append(desc)
		print("  FALHOU  " + desc + sufixo)

func _relatorio() -> void:
	print("")
	if _falhas.is_empty():
		print("TODOS OS TESTES PASSARAM (%d afirmacoes)" % _ok)
		quit(0)
	else:
		print("%d FALHA(S) de %d afirmacoes:" % [_falhas.size(), _ok + _falhas.size()])
		for f in _falhas:
			print("  - " + f)
		quit(1)
