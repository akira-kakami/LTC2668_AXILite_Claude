# LTC2668 AXI4-Lite Controller

Xilinx FPGA (Zynq / Vitis) 向け **LTC2668 16ch 16bit DAC** 制御モジュールです。  
AXI4-Lite スレーブ + SPI マスターを SystemVerilog RTL で実装し、Xilinx BSP (`Xil_Out32` / `Xil_In32`) ベースの C ドライバを付属します。
URL
https://claude.ai/chat/9a1d7436-34da-43a2-bbae-d15794dd84f7
---

## ファイル構成

```
.
├── component.xml            # Vivado IP-XACT 記述子（IP Creator 用）
├── hdl/
│   └── ltc2668_axi.sv       # AXI4-Lite スレーブ + SPI マスター RTL
├── xgui/
│   └── ltc2668_axi.tcl      # Vivado IP カスタマイズ GUI スクリプト
├── sim/
│   ├── ltc2668_axi_tb.sv        # SystemVerilog テストベンチ (スタンドアロン)
│   ├── ltc2668_axi_vip_tb.sv    # AXI VIP テストベンチ (Vivado xsim 用)
│   └── create_vip_project.tcl   # Vivado VIP シミュレーションプロジェクト自動生成
├── ltc2668_drv.h            # C ドライバ ヘッダ
├── ltc2668_drv.c            # C ドライバ 実装
├── ltc2668_example.c        # 使用例
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

### 方法 A: IP Creator（推奨）

IP Catalog に登録して Block Design から GUI で設定できます。

1. Vivado を開き、**Tools → Settings → IP → Repository** を選択
2. `+` ボタンでこのリポジトリのルートディレクトリを追加
3. IP Catalog に **LTC2668 AXI DAC Controller** が表示されることを確認
4. Block Design で **Add IP** → `LTC2668` を検索して追加
5. IP をダブルクリックして設定ダイアログを開き、パラメータを設定：
   - **AXI Address Width**: デフォルト 8（変更不要）
   - **SPI Clock Divider**: AXI クロックに応じて調整（100MHz → 4 で 12.5MHz）
6. `Run Connection Automation` で AXI4-Lite ポートを Zynq PS に自動接続
7. `spi_sck` / `spi_sdi` / `spi_cs_n` / `ldac_n` / `clr_n` を外部ポートに引き出し
8. Address Editor でベースアドレスを割り当て（例: `0x43C0_0000`）
9. Vitis でドライバファイル（`ltc2668_drv.h`, `ltc2668_drv.c`）をプロジェクトに追加

### 方法 B: 手動追加

1. `hdl/ltc2668_axi.sv` を RTL ソースとして追加
2. Block Design で **Add Module** → `ltc2668_axi` を追加
3. 以降は方法 A の手順 6〜9 と同様

---

## シミュレーション

### テストケース一覧（両テストベンチ共通）

| TC | 内容 |
|----|------|
| TC1 | リセット後のデフォルトレジスタ値確認（全 9 レジスタ） |
| TC2 | `SPI_CLK_DIV` 書き込み・読み返し |
| TC3 | `CMD_WRITE_N` – チャネル書き込み（SPI フレーム照合） |
| TC4 | `CMD_WRITE_UPDATE_N` – 書き込み＋即時更新 |
| TC5 | `CMD_UPDATE_ALL` – 全チャネル同時更新 |
| TC6 | `CMD_SPAN_N` – チャネル個別スパン設定 |
| TC7 | `CMD_SPAN_ALL` – 全チャネルスパン一括設定 |
| TC8 | `CMD_POWER_DOWN_N` – チャネルパワーダウン |
| TC9 | `CMD_TOGGLE_SEL` – トグル対象チャネル設定 |
| TC10 | `CMD_MUX_OUT` – MUX 出力設定 |
| TC11 | `LDAC_N` / `CLR_N` ハードウェア制御 |
| TC12 | SPI 転送中の `STATUS.BUSY` / `SPI_DONE` フラグ確認 |

---

### テストベンチ A: スタンドアロン (`ltc2668_axi_tb.sv`)

Vivado 以外のシミュレータでも動作します。

**ModelSim / Questa**
```bash
vlog -sv hdl/ltc2668_axi.sv sim/ltc2668_axi_tb.sv
vsim ltc2668_axi_tb -do "run -all; quit"
```

**Icarus Verilog + GTKWave**
```bash
iverilog -g2012 -o sim_out hdl/ltc2668_axi.sv sim/ltc2668_axi_tb.sv
vvp sim_out
gtkwave ltc2668_axi_tb.vcd
```

**Vivado xsim（手動設定）**
```tcl
create_project sim_ltc2668 ./sim_ltc2668 -part xc7z020clg400-1 -force
add_files      hdl/ltc2668_axi.sv
add_files -fileset sim_1 sim/ltc2668_axi_tb.sv
set_property top ltc2668_axi_tb [get_filesets sim_1]
launch_simulation
run all
```

---

### テストベンチ B: AXI VIP (`ltc2668_axi_vip_tb.sv`) ― Vivado 推奨

Xilinx AXI Verification IP (AXI VIP) を使用した Vivado 専用テストベンチです。
プロトコル準拠の AXI4-Lite マスタートランザクションを VIP エージェント API で生成します。

#### VIP テストベンチの構成

```
ltc2668_axi_vip_tb
  ├─ axi_vip_mst_0          ← AXI VIP (Master, AXI4LITE, 32-bit/8-bit addr)
  │    └─ axi_vip_mst_0_mst_t  mst_agent  ← VIP エージェント
  └─ ltc2668_axi (DUT)      ← テスト対象
```

#### 使用する主な VIP API

| API | 説明 |
|-----|------|
| `mst_agent.start_master()` | マスターエージェント起動 |
| `mst_agent.AXI4LITE_WRITE_BURST(addr, prot, data, resp)` | AXI4-Lite ライト |
| `mst_agent.AXI4LITE_READ_BURST(addr, prot, data, resp)` | AXI4-Lite リード |

#### 実行方法（ワンコマンド）

```bash
# Vivado コマンドライン（バッチモード）
vivado -mode batch -source sim/create_vip_project.tcl
```

```tcl
# Vivado Tcl Console から実行
source sim/create_vip_project.tcl
```

`create_vip_project.tcl` が行う処理：
1. Vivado プロジェクト `vivado_vip_sim/` を作成
2. AXI VIP IP（Master / AXI4LITE / 32-bit）を自動生成
3. テストベンチを sim_1 fileset に追加
4. `launch_simulation` → `run all` を自動実行

#### 再実行（プロジェクト作成済みの場合）

```tcl
relaunch_sim
run all
```

---

## ライセンス

MIT License
