class_name WeaponDb
extends RefCounted
## 武器台帳（docs/武器・ショップ設計.md v1 が正）。
## 原則：全武器とも「狙った点に飛ぶ正確さ」は同じ＝当てるのは腕。
## 差がつくのは 反動・ばらつき・装弾数・連射・リロード・弾速（扱いやすさと手数）だけ。
## 上位互換は作らない（得意な間合い・モードが違う）。エイム自動補助は商品にしない。

## 各エントリの "color" は武器のアクセント色（銃モデル・HUD武器名・ショップで共通に使う）。
## "snd" は発砲音のキャラクター（SfxBankが武器別サンプルを合成する）:
##   body_hi/body_lo=本体スイープの開始/終了Hz・dur=長さ(秒)・sub=低域の芯の量(0..1)
const WEAPONS := [
	{
		"id": "ghost",
		"name": "GHOST M24",
		"desc": "標準狙撃銃。クセがなく全て平均",
		"price": 0,
		"mag": 6,        # マガジン装弾数
		"total": 30,     # 総弾数（マガジン込み。尽きたらAMMO OUT対象）
		"speed": 850.0,  # 弾速(m/s)
		"cooldown": 0.45,   # 発射間隔(秒)
		"recoil": 1.0,      # 反動倍率
		"spread": 1.0,      # ばらつき倍率(SPREADトグルON時の散布角に掛かる)
		"reload": 1.6,      # リロード時間(秒)
		"auto": false,      # true=押しっぱなしで連射(フルオート)
		"color": Color(0.55, 0.58, 0.62),   # ガンメタルグレー
		"snd": {"body_hi": 700.0, "body_lo": 150.0, "dur": 0.18, "sub": 0.9},
	},
	{
		"id": "hawkeye",
		"name": "HAWKEYE X",
		"desc": "高精度ライフル。反動小・ばらつき小・高弾速＝超遠距離向き",
		"price": 1500,
		"mag": 5,
		"total": 30,
		"speed": 1000.0,
		"cooldown": 0.70,
		"recoil": 0.55,
		"spread": 0.45,
		"reload": 1.8,
		"auto": false,
		"color": Color(0.35, 0.62, 0.85),   # 精密のブルー
		"snd": {"body_hi": 600.0, "body_lo": 105.0, "dur": 0.26, "sub": 1.1},  # 重いドォン
	},
	{
		"id": "raptor",
		"name": "RAPTOR SEMI",
		"desc": "速射ライフル。装弾数多め・間隔短め＝動く標的と撃ち合い向き",
		"price": 900,
		"mag": 12,
		"total": 48,
		"speed": 780.0,
		"cooldown": 0.22,
		"recoil": 1.15,
		"spread": 1.35,
		"reload": 1.2,
		"auto": false,
		"color": Color(0.85, 0.55, 0.25),   # 俊敏のオレンジ
		"snd": {"body_hi": 950.0, "body_lo": 230.0, "dur": 0.13, "sub": 0.6},  # 軽快なパン
	},
	{
		"id": "tempest",
		"name": "TEMPEST LMG",
		"desc": "マシンガン。押しっぱなしで連射＝物量戦の主役。1発の精度は粗い",
		"price": 2600,
		"mag": 40,
		"total": 160,
		"speed": 700.0,
		"cooldown": 0.11,
		"recoil": 1.4,
		"spread": 1.8,
		"reload": 2.4,
		"auto": true,
		"color": Color(0.45, 0.72, 0.35),   # ミリタリーグリーン
		"snd": {"body_hi": 880.0, "body_lo": 260.0, "dur": 0.10, "sub": 0.5},  # 連射映えの短音
	},
]


static func by_id(id: String) -> Dictionary:
	for w in WEAPONS:
		if w.id == id:
			return w
	return WEAPONS[0]  # 不明idは初期武器（セーブ破損などの安全側）


## 装備中の武器（Settingsの保存値から引く）
static func equipped() -> Dictionary:
	return by_id(Settings.equipped_weapon)
