class_name Maqam
extends RefCounted
## Арабские лады и ритмы. Вынесено отдельно от синтеза, потому что это данные,
## а не звук: по ним же строятся подсказки в интерфейсе радио и выбор станции.
##
## Ступени заданы в полутонах от тоники и намеренно дробные. Четвертитон — не
## украшение: без ступени 3.5 раст превращается в обычный мажор, а без 1.5
## баяти — в фригийский лад. Именно эти полступени и слышны как «восточное».

## Ступени ладов. Значения — полутоны от тоники, включая октаву.
const SCALES := {
	&"rast": [0.0, 2.0, 3.5, 5.0, 7.0, 9.0, 10.5, 12.0],
	&"bayati": [0.0, 1.5, 3.0, 5.0, 7.0, 8.0, 10.0, 12.0],
	&"hijaz": [0.0, 1.0, 4.0, 5.0, 7.0, 8.0, 11.0, 12.0],
	&"saba": [0.0, 1.5, 3.0, 4.0, 7.0, 8.0, 10.0, 12.0],
	&"nahawand": [0.0, 2.0, 3.0, 5.0, 7.0, 8.0, 11.0, 12.0],
	&"kurd": [0.0, 1.0, 3.0, 5.0, 7.0, 8.0, 10.0, 12.0],
	&"ajam": [0.0, 2.0, 4.0, 5.0, 7.0, 9.0, 11.0, 12.0],
	&"sikah": [0.0, 1.5, 3.5, 5.5, 7.5, 9.0, 10.5, 12.0],
}

## Человеческие названия — для строки «сейчас в эфире» и для журнала.
const SCALE_NAMES := {
	&"rast": "раст",
	&"bayati": "баяти",
	&"hijaz": "хиджаз",
	&"saba": "саба",
	&"nahawand": "нахаванд",
	&"kurd": "курд",
	&"ajam": "аджам",
	&"sikah": "сика",
}

## Ритмические циклы (ика). Строка читается по восьмым:
##   D — дум, низкий удар ладонью в центр;
##   T — так, высокий щелчок по краю;
##   k — слабый так, подголосок;
##   . — пауза.
const RHYTHMS := {
	&"maqsum": "D.TTD.T.",
	&"baladi": "DD.TD.T.",
	&"ayyub": "D..TD.T.",
	&"saidi": "D.T.DDT.",
	&"malfuf": "D.TkT.Tk",
	&"wahda": "D...T...",
	&"samai": "D.T.D.TT",
}

const RHYTHM_NAMES := {
	&"maqsum": "максум",
	&"baladi": "балади",
	&"ayyub": "аюб",
	&"saidi": "саиди",
	&"malfuf": "мальфуф",
	&"wahda": "вахда",
	&"samai": "самаи",
}


static func scale_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in SCALES:
		out.append(key)
	out.sort()
	return out


static func rhythm_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in RHYTHMS:
		out.append(key)
	out.sort()
	return out


static func scale(id: StringName) -> Array:
	return SCALES.get(id, SCALES[&"bayati"])


static func rhythm(id: StringName) -> String:
	return RHYTHMS.get(id, RHYTHMS[&"maqsum"])


static func scale_name(id: StringName) -> String:
	return SCALE_NAMES.get(id, String(id))


static func rhythm_name(id: StringName) -> String:
	return RHYTHM_NAMES.get(id, String(id))


## Ступень лада по индексу, с выходом за октаву в обе стороны. Мелодия обязана
## уметь подниматься выше октавы, иначе фраза упирается в потолок и начинает
## топтаться на месте — это слышно за три такта.
static func degree(id: StringName, index: int) -> float:
	var steps: Array = scale(id)
	var span: int = steps.size() - 1
	if span <= 0:
		return 0.0
	var octave := int(floor(float(index) / float(span)))
	var position := index - octave * span
	return float(steps[position]) + float(octave) * 12.0


## Опорные ступени лада: на них фраза останавливается, и на них же строится
## бурдон. В арабской музыке это тоника, четвёртая и пятая — остальные ступени
## проходные, и заканчивать на них фразу звучит как оборванная мысль.
static func resting_degrees(id: StringName) -> Array[int]:
	match id:
		&"saba":
			return [0, 3, 7]
		&"sikah":
			return [0, 2, 4, 7]
		_:
			return [0, 3, 4, 7]
