class_name Balance
extends RefCounted

## Todos os numeros do GDD - Parte 1: Submundo.
## Funcoes puras, sem dependencia de cena: da para testar em --headless.

# ---------------------------------------------------------------- 7.3 PARRY
## Janela de parry: 0.2s antes do golpe atingir.
const PARRY_WINDOW := 0.2
## Falhar o parry deixa vulneravel por 0.5s.
const PARRY_FAIL_VULN := 0.5
## Atordoamento base do inimigo num parry bem-sucedido.
const PARRY_STUN := 0.5

## Tabela do 7.3: a resistencia do jogador decide o preco do parry.
## Cada faixa devolve a fracao de dano recebido, se atordoa o inimigo,
## se garante o critico de contra-ataque e a vulnerabilidade resultante.
const PARRY_TIERS := [
	{"min": 100, "dmg": 0.00, "stun": true,  "crit": true,  "vuln": 0.0, "nome": "Parry perfeito"},
	{"min": 75,  "dmg": 0.25, "stun": true,  "crit": true,  "vuln": 0.0, "nome": "Parry custa energia"},
	{"min": 50,  "dmg": 0.50, "stun": true,  "crit": true,  "vuln": 0.0, "nome": "Parry desgastante"},
	{"min": 25,  "dmg": 0.75, "stun": true,  "crit": true,  "vuln": 0.3, "nome": "Parry perigoso"},
	{"min": 1,   "dmg": 0.95, "stun": false, "crit": false, "vuln": 0.5, "nome": "Parry quase fatal"},
	{"min": 0,   "dmg": 1.00, "stun": false, "crit": false, "vuln": 1.0, "nome": "Parry impossível"},
]

## Resolve um parry bem-sucedido contra um golpe de `dano_bruto`.
static func parry_result(resistencia: int, dano_bruto: float) -> Dictionary:
	for tier in PARRY_TIERS:
		if resistencia >= int(tier["min"]):
			return {
				"dano": dano_bruto * float(tier["dmg"]),
				"atordoa": bool(tier["stun"]),
				"critico": bool(tier["crit"]),
				"vulneravel": float(tier["vuln"]),
				"queda": int(tier["min"]) == 0,
				"nome": String(tier["nome"]),
			}
	return {"dano": dano_bruto, "atordoa": false, "critico": false,
			"vulneravel": 1.0, "queda": true, "nome": "?"}

# ------------------------------------------------------------ 3.2 ADAPTACAO
## Curva de 51 consumos. A gravidade do efeito colateral cai em degraus.
static func consume_effect(consumos_previos: int) -> Dictionary:
	# `consumos_previos` = quantos o jogador ja fez ANTES deste.
	var n := consumos_previos + 1
	if n <= 20:
		return {"hp": 12, "vomito": true,  "desmaio": true,  "lentidao": 0.0,  "faixa": "1-20"}
	elif n <= 35:
		return {"hp": 8,  "vomito": false, "desmaio": false, "lentidao": 0.45, "faixa": "21-35"}
	elif n <= 50:
		return {"hp": 5,  "vomito": false, "desmaio": false, "lentidao": 0.0,  "faixa": "36-50"}
	return {"hp": 0, "vomito": false, "desmaio": false, "lentidao": 0.0, "faixa": "51+"}

## Cada consumo endurece o corpo. E o que destrava o parry perfeito (7.3).
const RESIST_POR_CONSUMO := 2
const RESIST_MAX := 120

static func resistencia_por_consumos(consumos: int) -> int:
	return mini(consumos * RESIST_POR_CONSUMO, RESIST_MAX)

# --------------------------------------------------------- 7.6 PROFICIENCIA
## Usos necessarios por nivel e o bonus de dano plano de cada um.
const PROF_USOS  := [0, 5, 15, 30, 50]
const PROF_BONUS := [0, 1, 2, 3, 5]
const PROF_NOMES := ["Iniciante", "Aprendiz", "Praticante", "Veterano", "Mestre"]

static func proficiency_level(usos: int) -> int:
	var nivel := 1
	for i in range(PROF_USOS.size()):
		if usos >= int(PROF_USOS[i]):
			nivel = i + 1
	return nivel

static func proficiency_bonus(usos: int) -> int:
	return int(PROF_BONUS[proficiency_level(usos) - 1])

# ---------------------------------------------------------------- 7.5 COMBO
const COMBO_GANHO := 0.09      # +9% por acerto consecutivo
const COMBO_JANELA := 2.0      # reseta apos 2s sem acertar
const SPEC_GANHO := 0.02       # +2% por golpe repetido com a mesma acao
const SPEC_TETO := 0.30        # ...ate +30%

static func damage_multiplier(combo: int, repeticoes: int) -> float:
	var c := COMBO_GANHO * float(maxi(combo, 0))
	var s := minf(SPEC_GANHO * float(maxi(repeticoes, 0)), SPEC_TETO)
	return 1.0 + c + s

# ------------------------------------------------------------------ 2 SPAWN
const SPAWN_INTERVALO := 10.0   # um monstro a cada 10s
const CAP_BASE := 30            # teto de monstros vivos
const MINIBOSS_KILLS := 5       # 5 mortes...
const MINIBOSS_JANELA := 60.0   # ...em menos de 60s invoca um Cavaleiro

## Derrotar Cavaleiros aumenta o teto de monstros no mapa.
static func monster_cap(cavaleiros_mortos: int) -> int:
	match cavaleiros_mortos:
		0: return CAP_BASE
		1: return CAP_BASE + 1
		2: return CAP_BASE + 3
		3: return CAP_BASE + 6
		_: return CAP_BASE + 9 + (cavaleiros_mortos - 4) * 3

# -------------------------------------------------------------- 4 BESTIARIO
## id, nome, hp, habilidade concedida ao ser comido, tipo e forma visual.
const BESTIARIO := [
	{"id":"rastejador", "nome":"Rastejador de Olhos", "hp":25, "hab":"Visão Sombria",
	 "tipo":"passiva", "vel":86,  "dano":7,  "cor":Color(0.42,0.36,0.20), "porte":0.50, "olhos":6},
	{"id":"carniceiro", "nome":"Carniceiro Ósseo", "hp":40, "hab":"Ossos Reforçados",
	 "tipo":"passiva", "vel":74,  "dano":11, "cor":Color(0.72,0.69,0.60), "porte":4.00, "olhos":2},
	{"id":"peleveloz", "nome":"Pele Veloz", "hp":20, "hab":"Agilidade Felina",
	 "tipo":"ativa",   "vel":150, "dano":6,  "cor":Color(0.55,0.24,0.20), "porte":1.50, "olhos":2},
	{"id":"ambutcher", "nome":"Ambutcher", "hp":25, "hab":"Invisibilidade",
	 "tipo":"ativa",   "vel":104, "dano":14, "cor":Color(0.30,0.26,0.30), "porte":1.00, "olhos":2},
	{"id":"vigia", "nome":"Vigia Carniça", "hp":45, "hab":"Radar",
	 "tipo":"ativa",   "vel":70,  "dano":9,  "cor":Color(0.36,0.42,0.26), "porte":1.10, "olhos":4},
	{"id":"toxoplasma", "nome":"Toxoplasma", "hp":30, "hab":"Toxina Paralisante",
	 "tipo":"ativa",   "vel":80,  "dano":8,  "cor":Color(0.40,0.52,0.22), "porte":1.00, "olhos":3},
	{"id":"deslizador", "nome":"Deslizador", "hp":22, "hab":"Teletransporte",
	 "tipo":"ativa",   "vel":120, "dano":7,  "cor":Color(0.28,0.34,0.44), "porte":0.90, "olhos":2},
	{"id":"aterror", "nome":"Aterrorizador", "hp":35, "hab":"Intimidação",
	 "tipo":"ativa",   "vel":92,  "dano":12, "cor":Color(0.46,0.18,0.24), "porte":1.15, "olhos":5},
	{"id":"regen", "nome":"Regenerador", "hp":50, "hab":"Regeneração Acelerada",
	 "tipo":"passiva", "vel":66,  "dano":10, "cor":Color(0.52,0.30,0.34), "porte":1.20, "olhos":2},
	{"id":"furioso", "nome":"Furioso", "hp":60, "hab":"Fúria Berserker",
	 "tipo":"ativa",   "vel":98,  "dano":16, "cor":Color(0.62,0.20,0.14), "porte":1.30, "olhos":2},
]

static func bestiario_por_id(id: String) -> Dictionary:
	for b in BESTIARIO:
		if String(b["id"]) == id:
			return b
	return {}

## 3.3: consumir a MESMA criatura de novo melhora a habilidade.
## 1o consumo destrava; no 5o o cooldown zera (ativa) ou o efeito satura (passiva).
const HAB_CONSUMOS_MAX := 5

static func habilidade_escala(consumos_da_criatura: int) -> float:
	# 1 -> 0.0 (base), 5+ -> 1.0 (maximo)
	if consumos_da_criatura <= 1:
		return 0.0
	return minf(float(consumos_da_criatura - 1) / float(HAB_CONSUMOS_MAX - 1), 1.0)

# ------------------------------------------------------------- 5 CAVALEIROS
const CAVALEIROS := [
	{"id":"guerra", "nome":"Guerra", "arma":"Espada Colossal", "hp":120,
	 "autoridade":"Instiga os monstros ao redor a atacar o jogador",
	 "hab":"Ímpeto Belicoso", "hab_desc":"+5% de dano por acerto consecutivo, até +50%",
	 "cor":Color(0.55,0.11,0.11)},
	{"id":"morte", "nome":"Morte", "arma":"Foice Pálida", "hp":100,
	 "autoridade":"Ressuscita monstros derrotados como espectros",
	 "hab":"Toque Fatal", "hab_desc":"10% de matar inimigos comuns em crítico",
	 "cor":Color(0.68,0.68,0.72)},
	{"id":"fome", "nome":"Fome", "arma":"Adaga Faminta", "hp":90,
	 "autoridade":"Dobra a velocidade da fome do jogador",
	 "hab":"Lâmina Faminta", "hab_desc":"Roubo de vida + 5% drenar comida",
	 "cor":Color(0.44,0.34,0.12)},
	{"id":"peste", "nome":"Peste", "arma":"Arco Pestilento", "hp":85,
	 "autoridade":"Drena 1 de resistência do jogador por segundo",
	 "hab":"Praga Corrompida", "hab_desc":"Veneno em área",
	 "cor":Color(0.34,0.50,0.20)},
	{"id":"conquista", "nome":"Conquista", "arma":"Cetro Dominador", "hp":130,
	 "autoridade":"Monstros comuns atacam uns aos outros",
	 "hab":"Mente Dominadora", "hab_desc":"15% de dominar um inimigo",
	 "cor":Color(0.50,0.42,0.14)},
]

static func cavaleiro_por_indice(i: int) -> Dictionary:
	return CAVALEIROS[clampi(i, 0, CAVALEIROS.size() - 1)]

## 30 segundos para inspecionar o corpo; a arma dropa 100% se der tempo.
const INSPECAO_JANELA := 30.0

## Impeto Belicoso (arma de Guerra): +5% por acerto consecutivo, teto +50%.
static func impeto_belicoso(acertos_consecutivos: int) -> float:
	return 1.0 + minf(0.05 * float(maxi(acertos_consecutivos, 0)), 0.50)

# ----------------------------------------------------------------- 7.2 ACOES
const ATK_LEVE := {"dano": 9.0, "alcance": 46.0, "arco": 1.5, "windup": 0.07, "recup": 0.20, "id": "leve"}
const ATK_FORTE := {"dano": 22.0, "alcance": 56.0, "arco": 2.1, "windup": 0.30, "recup": 0.48, "id": "forte"}

# --- socos (combo leve em sequencia)
const ATK_JAB := {"dano": 7.0, "alcance": 40.0, "arco": 1.2, "windup": 0.05, "recup": 0.14, "id": "jab", "kb": 55.0, "impacto": 0.18}
const ATK_DIRETO := {"dano": 9.0, "alcance": 46.0, "arco": 1.3, "windup": 0.07, "recup": 0.18, "id": "direto", "kb": 75.0, "impacto": 0.25}
const ATK_CRUZADO := {"dano": 12.0, "alcance": 44.0, "arco": 1.8, "windup": 0.09, "recup": 0.22, "id": "cruzado", "kb": 90.0, "impacto": 0.30}
const ATK_UPPERCUT := {"dano": 16.0, "alcance": 42.0, "arco": 1.4, "windup": 0.14, "recup": 0.30, "id": "uppercut", "kb": 130.0, "impacto": 0.45}

# --- chutes (combo de chutes em sequencia)
const ATK_CHUTE := {"dano": 11.0, "alcance": 52.0, "arco": 1.5, "windup": 0.10, "recup": 0.22, "id": "chute", "kb": 85.0, "impacto": 0.28}
const ATK_CHUTE_ALTO := {"dano": 15.0, "alcance": 50.0, "arco": 1.4, "windup": 0.14, "recup": 0.30, "id": "chute_alto", "kb": 110.0, "impacto": 0.38}
const ATK_CHUTE_GIRO := {"dano": 20.0, "alcance": 56.0, "arco": 2.4, "windup": 0.18, "recup": 0.38, "id": "chute_giro", "kb": 150.0, "impacto": 0.55}

# --- golpes corporais (ataque pesado direcional)
const ATK_CABECADA := {"dano": 14.0, "alcance": 28.0, "arco": 1.0, "windup": 0.08, "recup": 0.35, "id": "cabecada", "kb": 120.0, "impacto": 0.50}
const ATK_JOELHADA := {"dano": 13.0, "alcance": 34.0, "arco": 1.2, "windup": 0.10, "recup": 0.28, "id": "joelhada", "kb": 100.0, "impacto": 0.40}
const ATK_COTOVELADA := {"dano": 15.0, "alcance": 30.0, "arco": 1.6, "windup": 0.08, "recup": 0.25, "id": "cotovelada", "kb": 95.0, "impacto": 0.38}

const COMBO_SOCOS: Array = [ATK_JAB, ATK_DIRETO, ATK_CRUZADO, ATK_UPPERCUT]
const COMBO_CHUTES: Array = [ATK_CHUTE, ATK_CHUTE_ALTO, ATK_CHUTE_GIRO]
const COMBO_INPUT_JANELA := 0.5

static func golpe_pesado(agachado: bool, movendo_frente: bool) -> Dictionary:
	if agachado:
		return ATK_CABECADA
	if movendo_frente:
		return ATK_JOELHADA
	return ATK_COTOVELADA

const CARGA_MIN := 0.28
const DASH_VEL := 460.0
const DASH_DUR := 0.18
const DASH_INVULN := 0.22
const DASH_CD := 0.45
const CORRIDA_MULT := 1.5

# --- pulo
const PULO_DURACAO := 0.35
const PULO_INVULN := 0.20
const PULO_CD := 0.40

## 7.7: golpe pelas costas e critico garantido 2x.
const BACKSTAB_MULT := 2.0
const CRIT_MULT := 2.0

# ----------------------------------------------------------------- 7.7 VISAO
const CONE_ANGULO := 0.9599      # meia-abertura do cone (55 graus em radianos)
const CONE_ALCANCE := 300.0
const ALERTA_ATRASO := 0.5       # 0.5s de alerta antes de perseguir
const BUSCA_DURACAO := 5.0       # 5s procurando antes de voltar ao passivo

## O alvo esta dentro do cone de visao de quem olha?
static func dentro_do_cone(olho: Vector2, mira: Vector2, alvo: Vector2,
		alcance: float = CONE_ALCANCE) -> bool:
	var d := alvo - olho
	var dist := d.length()
	if dist > alcance or dist < 0.001:
		return false
	if mira.length() < 0.001:
		return false
	return absf(mira.normalized().angle_to(d / dist)) <= CONE_ANGULO

# ------------------------------------------------------------ 3.4 INVENTARIO
const SLOTS_INICIAIS := 2
const SLOTS_MAX := 5
