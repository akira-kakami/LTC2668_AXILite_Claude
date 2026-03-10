# LTC2668 AXI4-Lite Controller

Xilinx FPGA (Zynq / Vitis) 向け **LTC2668 16ch 16bit DAC** 制御モジュールです。  
AXI4-Lite スレーブ + SPI マスターを SystemVerilog RTL で実装し、Xilinx BSP (`Xil_Out32` / `Xil_In32`) ベースの C ドライバを付属します。

---

## ファイル構成

```
.
├── rtl/
│   └── ltc2668_axi.sv       # AXI4-Lite スレーブ + SPI マスター RTL
├── driver/
│   ├── ltc2668_drv.h        # C ドライバ ヘッダ
│   ├── ltc2668_drv.c        # C ドライバ 実装
│   └── ltc2668_example.c    # 使用例
└── README.md
```

---

## ハードウェア仕様

| 項目 | 内容 |
|------|------|
| 対象デバイス | LTC2668-16（16ch 16bit DAC） |
| インターフェース | AXI4-Lite スレーブ |
| SPI モード | CPOL=0, CPHA=0（Mode 0） |
| SPI フレーム長 | 32bit（CMD[3:0] \| ADDR[3:0] \| DATA[15:0] \| X[7:0]） |
| デフォルト SPI クロック | AXI クロック / 8（100MHz 時 12.5MHz） |
| 対応スパン | 0〜5V / 0〜10V / ±5V / ±10V / ±2.5V |

---

## レジスタマップ

| オフセット | 名前 | アクセス | 説明 |
|-----------|------|---------|------|
| `0x00` | CTRL | R/W | ソフトリセット / LDAC_N / CLR_N 制御 |
| `0x04` | CH_SEL | R/W | 対象チャネル選択（0–15） |
| `0x08` | DAC_DATA | R/W | 16bit DAC 出力コード |
| `0x0C` | SPAN | R/W | チャネル個別スパンコード |
| `0x10` | CMD | R/W | コマンド（**書き込みで SPI 送信トリガ**） |
| `0x14` | STATUS | R | BUSY[0] / SPI_DONE[1]（読み出し専用） |
| `0x18` | SPI_CLK_DIV | R/W | SPI クロック分周比（デフォルト: 4） |
| `0x1C` | TOGGLE_SEL | R/W | トグル対象チャネルマスク |
| `0x20` | MUX_CTRL | R/W | MUX 出力チャネル選択 |
| `0x24` | GLOBAL_SPAN | R/W | 全チャネル共通スパン |

### CTRL レジスタ ビット定義

| ビット | 名前 | 説明 |
|--------|------|------|
| [1] | `SOFT_RST` | 1: IP コアをソフトリセット |
| [2] | `LDAC_LOW` | 1: `LDAC_N` ピンをアサート（Low） → 全 CH 同期更新 |
| [3] | `CLR_LOW` | 1: `CLR_N` ピンをアサート（Low） → 全 CH 出力クリア |

---

## RTL ポート一覧

```systemverilog
// AXI4-Lite
input  s_axi_aclk, s_axi_aresetn
// ... (標準 AXI4-Lite 信号)

// SPI
output spi_sck, spi_sdi, spi_cs_n
input  spi_sdo

// ハードウェア制御
output ldac_n, clr_n
```

### パラメータ

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| `AXI_ADDR_WIDTH` | 8 | AXI アドレスバス幅 |
| `AXI_DATA_WIDTH` | 32 | AXI データバス幅 |
| `SPI_CLK_DIV_DEFAULT` | 4 | SPI クロック分周初期値 |

---

## C ドライバ 使い方

### 依存

- Xilinx Vitis / SDK（`xil_io.h`, `xil_types.h`, `sleep.h`）

### 初期化

```c
#include "ltc2668_drv.h"

#define LTC2668_BASE_ADDR  0x43C00000UL  // Vivado で割り当てたアドレス

ltc2668_dev_t dac;
ltc2668_init(&dac, LTC2668_BASE_ADDR);
```

### 電圧出力（1 チャネル）

```c
// ±10V スパンで 2.5V を出力
ltc2668_set_span_all(&dac, LTC2668_SPAN_M10_TO_10V);

u16 code = ltc2668_voltage_to_code(2.5f, LTC2668_SPAN_M10_TO_10V);
ltc2668_write_update_ch(&dac, 0, code);  // CH0 に即時反映
```

### 複数チャネル同期更新

```c
// 入力レジスタに書き込み（出力はまだ変化しない）
ltc2668_write_ch(&dac, 0, ltc2668_voltage_to_code( 5.0f, LTC2668_SPAN_M10_TO_10V));
ltc2668_write_ch(&dac, 1, ltc2668_voltage_to_code(-5.0f, LTC2668_SPAN_M10_TO_10V));
ltc2668_write_ch(&dac, 2, ltc2668_voltage_to_code( 0.0f, LTC2668_SPAN_M10_TO_10V));

// 全チャネルを同時に出力反映
ltc2668_update_all(&dac);
```

### ハードウェア LDAC による同期更新

SPI コマンドより低レイテンシで同期更新できます。

```c
// 値をロード
ltc2668_write_ch(&dac, 0, code0);
ltc2668_write_ch(&dac, 1, code1);

// LDAC_N パルス → 全 CH 同時出力
Xil_Out32(LTC2668_BASE_ADDR + LTC2668_REG_CTRL, LTC2668_CTRL_LDAC_LOW);
usleep(1);
Xil_Out32(LTC2668_BASE_ADDR + LTC2668_REG_CTRL, 0);
```

### 主要 API 一覧

| 関数 | 説明 |
|------|------|
| `ltc2668_init()` | 初期化・ソフトリセット |
| `ltc2668_set_clk_div()` | SPI クロック分周比設定 |
| `ltc2668_write_ch()` | 入力レジスタ書き込み（出力保留） |
| `ltc2668_write_update_ch()` | 書き込み＋即時出力更新 |
| `ltc2668_update_all()` | 全チャネル同時出力更新 |
| `ltc2668_set_span_ch()` | チャネル個別スパン設定 |
| `ltc2668_set_span_all()` | 全チャネルスパン一括設定 |
| `ltc2668_power_down_ch()` | チャネルパワーダウン |
| `ltc2668_set_toggle_sel()` | トグル対象チャネル設定 |
| `ltc2668_set_mux()` | MUX 出力モニタ設定 |
| `ltc2668_voltage_to_code()` | 電圧 → 16bit コード変換 |
| `ltc2668_code_to_voltage()` | 16bit コード → 電圧変換 |
| `ltc2668_nop()` | NOP 送信（デイジーチェーン同期用） |

---

## Vivado 組み込み手順

1. `ltc2668_axi.sv` を RTL ソースとして追加
2. Block Design で **Add Module** → `ltc2668_axi` を追加
3. AXI4-Lite ポートを Zynq PS の `M_AXI_GP0` に接続
4. `spi_sck` / `spi_sdi` / `spi_cs_n` を外部ポートに引き出し
5. Address Editor でベースアドレスを割り当て（例: `0x43C0_0000`）
6. Vitis でドライバファイル 3 点をプロジェクトに追加

---

## ライセンス

MIT License
