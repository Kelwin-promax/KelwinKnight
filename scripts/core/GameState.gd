extends Node

const BalanceRules = preload("res://scripts/core/Balance.gd")
const GamePalette = preload("res://scripts/core/Palette.gd")

## Estado de uma run. Autoload: sobrevive a troca de cena, mas NAO sobrevive
## a morte - 2 diz que morrer reseta tudo, inclusive o contador de consumos
## e o inventario. Nao existe progressao entre runs.

signal stats_mudaram()
signal log_novo(texto: String, cor: Color)
signal impacto(forca: float, pos: Vector2, dir: Vector2)

# --------------------------------------------------------------------- vida
var hp_max: float = 100.0
var hp: float = 100.0

# --------------------------------------------------- 3.2 consumo e adaptacao
var consumos_total: int = 0
var consumos_por_criatura: Dictionary = {}   # id -> int
var habilidades: Dictionary = {}             # id da criatura -> {nome, tipo, consumos}

# ------------------------------------------------------- 7.6 proficiencia
var proficiencia: Dictionary = {}            # id da acao -> usos bem-sucedidos

# ------------------------------------------------------------ 3.4 inventario
var slots: int = BalanceRules.SLOTS_INICIAIS
var inventario: Array[String] = []

# -------------------------------------------------------------- 5 cavaleiros
var armas_na_alma: Array[String] = []        # armas nao ocupam slots
var cavaleiros_mortos: int = 0
var arma_equipada: String = ""               # "" = combate desarmado

# ----------------------------------------------------- 2 ritmo da dificuldade
var mortes_recentes: Array[float] = []       # timestamps para o gatilho do mini-boss
var minibosses_vivos: int = 0
var tempo_run: float = 0.0
var monstros_mortos: int = 0

## 3.2: a resistencia sobe com o que voce consegue engolir.
var resistencia: int:
	get:
		return BalanceRules.resistencia_por_consumos(consumos_total)

## Permadeath. Zera tudo e comeca outra vez com fome.
func reset_run() -> void:
	hp_max = 100.0
	hp = hp_max
	consumos_total = 0
	consumos_por_criatura.clear()
	habilidades.clear()
	proficiencia.clear()
	slots = BalanceRules.SLOTS_INICIAIS
	inventario.clear()
	armas_na_alma.clear()
	arma_equipada = ""
	cavaleiros_mortos = 0
	mortes_recentes.clear()
	minibosses_vivos = 0
	tempo_run = 0.0
	monstros_mortos = 0
	stats_mudaram.emit()

func mensagem(texto: String, cor: Color = GamePalette.HUD_TEXTO) -> void:
	log_novo.emit(texto, cor)

# ------------------------------------------------------------------ consumo
## Come uma criatura. Devolve o efeito colateral aplicado, ja considerando
## em que ponto da curva de 51 o jogador esta.
func consumir(id_criatura: String) -> Dictionary:
	var efeito: Dictionary = BalanceRules.consume_effect(consumos_total)
	consumos_total += 1

	var n := int(consumos_por_criatura.get(id_criatura, 0)) + 1
	consumos_por_criatura[id_criatura] = n

	var info: Dictionary = BalanceRules.bestiario_por_id(id_criatura)
	var primeira := not habilidades.has(id_criatura)
	if not info.is_empty():
		habilidades[id_criatura] = {
			"nome": String(info["hab"]),
			"tipo": String(info["tipo"]),
			"consumos": n,
			"escala": BalanceRules.habilidade_escala(n),
		}

	efeito["primeira_vez"] = primeira
	efeito["habilidade"] = String(info.get("hab", ""))
	efeito["criatura"] = String(info.get("nome", id_criatura))
	efeito["consumos_criatura"] = n

	hp = maxf(1.0, hp - float(efeito["hp"]))
	stats_mudaram.emit()
	return efeito

# ------------------------------------------------------------- proficiencia
## Registra um golpe acertado e devolve `true` se subiu de nivel.
func registrar_uso(acao: String) -> bool:
	var antes: int = BalanceRules.proficiency_level(int(proficiencia.get(acao, 0)))
	proficiencia[acao] = int(proficiencia.get(acao, 0)) + 1
	var depois: int = BalanceRules.proficiency_level(int(proficiencia[acao]))
	if depois > antes:
		stats_mudaram.emit()
		return true
	return false

func bonus_proficiencia(acao: String) -> int:
	return BalanceRules.proficiency_bonus(int(proficiencia.get(acao, 0)))

func nivel_proficiencia(acao: String) -> int:
	return BalanceRules.proficiency_level(int(proficiencia.get(acao, 0)))

# ------------------------------------------------ 2 gatilho do mini-boss
## Marca uma morte e diz se isso invocou um Cavaleiro:
## 5 monstros em menos de 60 segundos.
func registrar_morte_de_monstro() -> bool:
	monstros_mortos += 1
	mortes_recentes.append(tempo_run)
	# descarta o que saiu da janela
	while mortes_recentes.size() > 0 and tempo_run - mortes_recentes[0] > BalanceRules.MINIBOSS_JANELA:
		mortes_recentes.remove_at(0)
	if mortes_recentes.size() >= BalanceRules.MINIBOSS_KILLS:
		mortes_recentes.clear()   # consome o gatilho
		return true
	return false

func teto_de_monstros() -> int:
	return BalanceRules.monster_cap(cavaleiros_mortos)

# ------------------------------------------------------------------- armas
func ganhar_arma(nome_arma: String) -> void:
	if not armas_na_alma.has(nome_arma):
		armas_na_alma.append(nome_arma)
	arma_equipada = nome_arma
	stats_mudaram.emit()

## 5: as armas ficam na alma, entao alternar nao mexe no inventario.
func alternar_arma() -> void:
	if armas_na_alma.is_empty():
		return
	if arma_equipada == "":
		arma_equipada = armas_na_alma[0]
	else:
		var i := armas_na_alma.find(arma_equipada)
		if i == armas_na_alma.size() - 1:
			arma_equipada = ""      # volta ao corpo a corpo
		else:
			arma_equipada = armas_na_alma[i + 1]
	stats_mudaram.emit()

## Acao usada para contar proficiencia: o corpo e a arma sobem separados.
func acao_de_ataque(pesado: bool) -> String:
	var base := "forte" if pesado else "leve"
	if arma_equipada == "":
		return "punho_" + base
	return arma_equipada.to_lower().replace(" ", "_") + "_" + base

# --------------------------------------------------------------- inventario
func cabe_no_inventario() -> bool:
	return inventario.size() < slots

func adicionar_item(item: String) -> bool:
	if not cabe_no_inventario():
		return false
	inventario.append(item)
	stats_mudaram.emit()
	return true

## 3.4: com resistencia abaixo de 100, cada item pesa e te deixa lento.
func penalidade_de_peso() -> float:
	if resistencia >= 100:
		return 1.0
	return maxf(0.55, 1.0 - 0.07 * float(inventario.size()))
