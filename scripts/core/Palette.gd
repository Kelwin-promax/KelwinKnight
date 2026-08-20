class_name Palette
extends RefCounted

## 1.2: pixel art suja, low-res. Marrom, vermelho escuro, preto, cinza,
## verde putrido. Nada de cor saturada alegre - o Submundo e um purgatorio.

const VAZIO      := Color(0.031, 0.027, 0.031)  # fora do mapa, o nada
const PEDRA      := Color(0.106, 0.090, 0.094)  # corpo da parede
const PEDRA_TOPO := Color(0.286, 0.243, 0.224)  # face da parede virada pro jogador
const CHAO       := Color(0.243, 0.204, 0.192)  # carne e terra batida
const CHAO_ALT   := Color(0.231, 0.192, 0.184)  # xadrez do chao (quase imperceptivel)
const MANCHA     := Color(0.259, 0.106, 0.098)  # sangue seco no chao

const CARNE      := Color(0.451, 0.290, 0.259)
const OSSO       := Color(0.741, 0.706, 0.612)
const SANGUE     := Color(0.431, 0.055, 0.055)
const SANGUE_VIVO := Color(0.702, 0.106, 0.086)
const PUTRIDO    := Color(0.427, 0.482, 0.196)  # verde de infeccao
const FERRO      := Color(0.365, 0.365, 0.396)
const CONTORNO   := Color(0.055, 0.043, 0.047)

# Jogador: um farrapo palido, o unico tom frio do mapa.
const PELE       := Color(0.671, 0.541, 0.463)
const TRAPO      := Color(0.310, 0.310, 0.353)
const TRAPO_ESC  := Color(0.212, 0.216, 0.259)
const LAMINA     := Color(0.600, 0.616, 0.647)

# HUD
const HUD_FUNDO  := Color(0.055, 0.047, 0.051, 0.85)
const HUD_TEXTO  := Color(0.741, 0.706, 0.643)
const HUD_FRACO  := Color(0.400, 0.376, 0.353)
const HUD_VIDA   := Color(0.596, 0.098, 0.098)
const HUD_RESIST := Color(0.451, 0.494, 0.231)
const HUD_DESTAQUE := Color(0.780, 0.667, 0.310)
const ALERTA     := Color(0.851, 0.220, 0.157)
const BUSCA      := Color(0.808, 0.678, 0.263)

## Escurece/clareia mantendo o ar sujo (nada de branco puro).
static func sombra(c: Color, f: float = 0.55) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)

static func luz(c: Color, f: float = 0.25) -> Color:
	return Color(
		minf(c.r + f, 0.93),
		minf(c.g + f * 0.92, 0.90),
		minf(c.b + f * 0.85, 0.87),
		c.a)
