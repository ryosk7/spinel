# PLAN: Spinel AOT Compiler

Ruby source → Prism AST → whole-program type inference → standalone C executable.
No runtime dependencies (no mruby, no GC library — GC is generated inline).
Regexp対応プログラムのみ libonig をリンク。

詳細設計は `ruby_aot_compiler_design.md` を参照。

---

## 現状 (Status)

### コンパイラアーキテクチャ (~12600行のC, 6ファイル)

```
src/
├── codegen.h  (365行) — 型定義、構造体、共有関数宣言
├── codegen.c (2318行) — オーケストレータ、ユーティリティ、クラス解析、
│                         キャプチャ解析、ラムダ、require処理
├── type.c    (2093行) — 型推論、型解決、型ヘルパー
├── expr.c    (3692行) — 式コード生成
├── stmt.c    (1938行) — 文コード生成
└── emit.c    (2152行) — Cコード出力 (ヘッダ、構造体、メソッド)
```

- Prism (libprism) によるRubyパース
- 多パスコード生成:
  1. クラス/モジュール/関数解析 (継承チェーン、mixin解決、Struct.new展開含む) — `codegen.c`
  2. 全変数・パラメータ・戻り値の型推論 (関数間解析) — `type.c`
  3. C構造体・メソッド関数の生成 (GCスキャン関数含む) — `emit.c`
  4. ラムダ/クロージャのキャプチャ解析・コード生成 — `codegen.c`
  5. yield/ブロックのコールバック関数生成 (block_given?対応) — `emit.c`
  6. 正規表現パターンのプリコンパイル (oniguruma) — `emit.c`
  7. main()のトップレベルコード生成 — `codegen.c`
- マーク&スイープGC (シャドウスタック、ファイナライザ)
- setjmp/longjmpベース例外処理 (クラス例外階層対応)
- アリーナアロケータ (ラムダ/クロージャ用)

### サポート済み言語機能

| カテゴリ | 機能 |
|---------|------|
| **OOP** | クラス定義、インスタンス変数、メソッド定義 |
| | 継承 (`class Dog < Animal`)、`super` |
| | `include` (mixin) — モジュールのインスタンスメソッド取り込み |
| | `attr_accessor` / `attr_reader` / `attr_writer` |
| | クラスメソッド (`def self.foo`) |
| | `Struct.new(:x, :y)` — 合成クラス生成 |
| | `Struct.new(keyword_init: true)` — キーワード引数コンストラクタ |
| | `alias` — メソッド別名 |
| | `freeze`/`frozen?` — AOTでは全値がfrozen扱い |
| | getter/setter自動インライン化 |
| | コンストラクタ (`.new`)、型付きオブジェクトへのメソッド呼び出し |
| | モジュール (状態変数 + メソッド + 定数) |
| | Module constants (`Module::CONST`) — 型推論付き |
| **イントロスペクション** | `is_a?` — 継承チェーンをコンパイル時に静的解決 |
| | `respond_to?` — メソッドテーブルをコンパイル時に静的解決 |
| | `nil?` — nil以外は常にFALSE |
| | `defined?` — 変数定義チェック (コンパイル時) |
| **ブロック/クロージャ** | `yield`、ブロック付きメソッド呼び出し (キャプチャ変数) |
| | `block_given?` — ブロックの有無チェック |
| | `Array#each/map/select/reject/reduce/inject` (インライン化) |
| | `Array#count(block)/sort_by/min_by/max_by/any?/find/filter_map` |
| | `StrArray#count(block)/any?/find/max_by/filter_map` |
| | `Hash#each` (キー/値ペア) |
| | `Integer#times/upto/downto` with block → C forループ |
| | `-> x { body }` ラムダ → Cクロージャ (キャプチャ解析) |
| **制御** | while, until, if/elsif/else, unless |
| | case/when/else (値、複数値、Range条件) |
| | for..in + Range, loop do |
| | break, next, return |
| | ternary, and/or/not |
| | `&.` (safe navigation operator) |
| | `__LINE__`, `__FILE__`, `__method__`, `defined?` |
| | `catch`/`throw` (タグ付き非局所脱出) |
| **例外処理** | begin/rescue/ensure/retry |
| | `raise "message"`, `raise ClassName, "message"` |
| | `rescue ClassName => e` (クラス階層チェック付き) |
| | 複数rescue節の連鎖 |
| | volatile変数でlongjmpの値保存 |
| **引数** | 位置引数、デフォルト値 (`def foo(x = 10)`) |
| | キーワード引数 (`def foo(name:, greeting: "Hello")`) |
| | 可変長引数/スプラット (`def sum(*nums)`) |
| **型** | Integer, Float, Boolean, String, Symbol, nil → アンボックスC型 |
| | 値型 (Vec: 3 floats → 値渡し) vs ポインタ型 |
| **コレクション** | sp_IntArray (push/pop/shift/dup/reverse!/each/map/select/reject/reduce) |
| | Array#first/last/include?/sort/sort!/sort_by/min/max/min_by/max_by/sum/count/length |
| | sp_StrIntHash (文字列キー→整数値、each/has_key?/delete) |
| | sp_StrArray (文字列配列、split結果用) |
| | O(1) shift (デキュー方式のstartオフセット) |
| **正規表現** | `/pattern/` リテラル → onigurumaプリコンパイル |
| | `=~`、`$1`-`$9` キャプチャグループ |
| | `match?`, `gsub`, `sub`, `scan` (ブロック付き), `split` |
| **演算** | 算術 (+, -, *, /, %, **), 比較, ビット演算 |
| | 単項マイナス, 複合代入 (+=, <<=) |
| | Math.sqrt/cos/sin → C math関数 |
| | Integer#abs/even?/odd?/zero?/positive?/negative?/clamp |
| | Float#abs/ceil/floor/round |
| **文字列** | リテラル、補間 → printf |
| | 35+メソッド: length, upcase, downcase, strip, lstrip, rstrip, reverse |
| |   gsub, sub, split, capitalize, chomp |
| |   include?, start_with?, end_with?, count, match?, empty? |
| |   ljust, rjust, center, tr, delete, squeeze |
| |   chars, bytes, to_f, to_i, hex, oct, slice, dup |
| |   +, <<, * (連結、追記、繰り返し) |
| |   ==, !=, <, > (strcmp比較) |
| |   `[]` (文字インデックス), `[range]` (範囲スライス) |
| | sp_String (ミュータブル): 上記に加え replace, clear, 25+メソッド委譲 |
| | Integer#to_s, Integer#chr |
| **I/O** | puts, print, printf, putc, p → stdio |
| | puts: Integer, Float, Boolean, String対応 (末尾改行のRuby互換) |
| | File.read, File.write, File.exist?, File.delete |
| | File.open with block, File.join, File.basename, File.dirname |
| | File.expand_path, File.size, File.mtime, File.ctime, File.readlink |
| | File.rename, Dir.glob, Dir.home, ENV[] |
| | system(), backtick (`cmd`), $stdin.getc |
| **GC** | マーク&スイープ (非値型オブジェクト・配列・ハッシュ用) |
| | シャドウスタックルート管理, ファイナライザ |
| | GC不要なプログラムではGCコード省略 |

### テストプログラム (53例自動テスト / 54ファイル)

| プログラム | テスト対象 |
|-----------|-----------|
| bm_so_mandelbrot | while、ビット演算、PBM出力 |
| bm_ao_render | 6クラス、モジュール、GC |
| bm_so_lists | 配列操作 (push/pop/shift)、GC |
| bm_fib | 再帰、関数型推論 |
| bm_app_lc_fizzbuzz | 1201クロージャ、アリーナ |
| bm_mandel_term | 関数間呼び出し、putc |
| bm_yield | yield/ブロック、each/map/select |
| bm_case | case/when、unless、next、デフォルト引数 |
| bm_inherit | 継承、super |
| bm_rescue | rescue/raise/ensure/retry |
| bm_hash | Hash操作 |
| bm_strings | Symbol、基本文字列メソッド |
| bm_strings2 | 高度な文字列メソッド、split、比較 |
| bm_strings3 | ljust/rjust/center/tr/delete/squeeze/chars/bytes/slice/[range] |
| bm_numeric | 数値メソッド (abs, ceil, even?, **) |
| bm_attr | attr_accessor、for..in、loop、クラスメソッド |
| bm_kwargs | キーワード引数、スプラット |
| bm_mixin | include (mixin) |
| bm_misc | upto/downto、String <<、配列引数 |
| bm_regexp | 正規表現 (=~, $1, match?, gsub, sub, scan, split) |
| bm_introspect | is_a?, respond_to?, nil?, positive?, negative? |
| bm_struct | Struct.new |
| bm_struct_kw | Struct.new(keyword_init: true) |
| bm_array2 | Array#reject/first/last/include? |
| bm_array3 | Array#count(block)/sort_by/min_by/max_by, StrArray#count |
| bm_sort_reduce | Array#sort/min/max/sum/reduce/inject |
| bm_control | __LINE__, __FILE__, defined? |
| bm_exceptions | raise ClassName, rescue ClassName, 例外階層 |
| bm_block2 | block_given?, ブロック付きyield呼び出し |
| bm_fileio | File.read/write/exist?/delete |
| bm_fileopen | File.open with block |
| bm_catch | catch/throw (タグ付き非局所脱出) |
| bm_features | __method__, freeze/frozen? |
| bm_comparable | Comparable演算子メソッド、alias |
| bm_range | Range as object (first, last, each, include?, to_a) |
| bm_time | Time.now, Time.at, to_i, 差分 |
| bm_enumerable | Enumerable, yield付きeachメソッド |
| bm_method | method(:name) → sp_Proc |
| bm_strindex | String#[] (文字インデックス) |
| bm_stdlib | ARGV, $stderr, srand/rand, exit |
| bm_proc | &block, proc {}, Proc.new, Proc#call |
| bm_poly | 多相変数 (sp_RbValue Phase 1) |
| bm_poly2 | 異種配列, bimorphicダックタイピング (Phase 2) |
| bm_pattern | パターンマッチ case/in (Phase 3) |
| bm_mutable_str3 | sp_String 追加メソッド (downcase, strip, start_with?等) |
| bm_safe_nav | &. (safe navigation operator) |
| bm_constants | モジュール定数、トップレベル定数 |

### ベンチマーク結果

| ベンチマーク | CRuby | mruby | Spinel AOT | 高速化 | メモリ |
|-------------|-------|-------|------------|--------|--------|
| mandelbrot (600×600) | 1.14s | 3.18s | 0.02s | 57× | <1MB |
| ao_render (64×64 AO) | 3.55s | 13.69s | 0.07s | 51× | 2MB |
| so_lists (300×10K) | 0.44s | 2.01s | 0.02s | 22× | 2MB |
| fib(34) | 0.55s | 2.78s | 0.01s | 55× | <1MB |
| lc_fizzbuzz (Church) | 28.96s | — | 1.55s | 19× | arena |
| mandel_term | 0.05s | 0.05s | ~0s | 50×+ | <1MB |

生成バイナリは完全スタンドアロン (libc + libm のみ、mruby不要)。
Regexp使用時のみ libonig をリンク。

---

## 全Rubyコンパイルへの残課題 (10カテゴリ)

| # | カテゴリ | 状態 | 次のアクション |
|---|---------|------|-------------|
| 1 | **動的型付け / ポリモーフィズム** | **Phase 7完了** ✅ | NaN-boxing, 3段階dispatch |
| 2 | **require / load / gem** | **require_relative完了** ✅ | load/gemは未着手 |
| 3 | **Block/Proc完全性** | **完了** ✅ | yield, &block, Proc.new, proc {}, method(:name) |
| 4 | **組込クラス** | **ほぼ完了** ✅ | File, Time, Range, Enumerable 対応済み |
| 5 | **完全なString** | **大幅拡充** ✅ | 35+メソッド、sp_String 25+メソッド委譲 |
| 6 | **オブジェクトシステム完全性** | 一部完了 | Comparable完了。module constants完了。method_missing等はフォールバック |
| 7 | **制御フロー完全性** | **完了** ✅ | catch/throw, &. 含む全制御フロー |
| 8 | **パターンマッチ** | **完了** ✅ | case/in (型/値/nil/alternation) |
| 9 | **例外階層** | **完了** ✅ | raise ClassName, rescue ClassName, 継承チェック |
| 10 | **GC完全性** | 一部完了 | 文字列GC (sp_String), 世代別GC |

### 完了した項目
- ✅ **sp_RbValue Phase 1**: 多相変数、boxing/unboxing、sp_poly_puts、nil?
- ✅ **sp_RbValue Phase 2**: 異種配列(sp_RbArray)、bimorphicダックタイピング、クラスタグ
- ✅ **パターンマッチ**: `case/in` (型チェック、値マッチ、AlternationPattern、nil)
- ✅ **Block/Proc**: yield, block_given?, &block, proc {}, Proc.new, Proc#call, method(:name)
- ✅ **Comparable**: 演算子メソッドC名サニタイズ (<=> → _cmp等)、self参照
- ✅ **Range as object**: first, last, each, include?, to_a, sum
- ✅ **Time**: Time.now, Time.at, to_i, 差分
- ✅ **Enumerable**: yield付きeachメソッドのブロック対応
- ✅ `catch`/`throw`, `alias`, `freeze`/`frozen?`, `__method__`, `sleep`
- ✅ `ARGV`, `$stderr.puts`, `exit`, `srand`/`rand`, `String#[]`
- ✅ `File.read/write/exist?/delete`
- ✅ `File.open` with block, `File.join/basename/dirname/expand_path/size/mtime/ctime/readlink/rename`
- ✅ `Dir.glob`, `Dir.home`, `ENV[]`, `system()`, backtick, `$stdin.getc`
- ✅ `Array#sort/sort!/min/max/sum/reduce/inject/join/uniq`
- ✅ `Array#count(block)/sort_by/min_by/max_by`, `StrArray#count(block)`
- ✅ `String#ljust/rjust/center/lstrip/rstrip/tr/delete/squeeze/chars/bytes/to_f/slice/hex/oct/dup/[range]`
- ✅ `sp_String` 25+メソッド委譲: downcase, strip, chomp, start_with?, etc.
- ✅ `Struct.new(keyword_init: true)` — キーワード引数コンストラクタ
- ✅ `&.` (safe navigation operator) — 単相コードでは透過的に動作
- ✅ Module constants (`Module::CONST`) — 型推論付き (STRING/BOOLEAN/HASH対応)
- ✅ **NaN-boxing** (8バイト favor pointer, JSC方式)
- ✅ **ソースコード分割**: codegen.c (12200行) → 5ファイル (最大3700行)

### 巨大ゴール: lrama コンパイル

71ファイル / 14,133行のRubyコード (LALR(1)パーサジェネレータ) をコンパイル対象とする。
ソース: `/home/matz/work/mruby/tools/lrama/`

#### lrama分析で判明した不足機能 (優先度順)

**Phase A: 言語基盤 (依存なしで実装可、多くのファイルに影響)**

| # | 機能 | lrama使用数 | 難易度 |
|---|------|------------|--------|
| A1 | `private` キーワード (メソッド可視性、無視でOK) | 22ファイル | 低 |
| A2 | `case` without expression (bare case) | 8ファイル | 低 |
| A3 | `Array.new(n, val)` コンストラクタ | 7箇所 | 低 |
| A4 | `Array#compact` (nil除去) | 6箇所 | 低 |
| A5 | `Array#flatten` | 6箇所 | 低 |
| A6 | `Array#unshift` | 多数 | 低 |
| A7 | `Array#reverse` | 2箇所 | 低 |
| A8 | `Hash#values` / `Hash#keys` / `Hash#key?` | 多数 | 低 |
| A9 | `Hash#merge` (ブロックなし) | 多数 | 中 |
| A10 | `Hash#transform_values` | 6箇所 | 中 |
| A11 | `.to_h` (配列→Hash変換) | 6箇所 | 中 |
| A12 | `alias :new_name :old_name` | 5ファイル | 低 |
| A13 | `%w[...]` / `%i[...]` リテラル | 3箇所 | 低 |
| A14 | `Float::INFINITY` | 2箇所 | 低 |
| A15 | `__dir__` | 3箇所 | 低 |
| A16 | `abort` / `exit(n)` / `STDERR` / `STDIN` | 各数箇所 | 低 |
| A17 | `group_by` | 4箇所 | 中 |
| A18 | `.zip` | 2箇所 | 中 |
| A19 | `.dup` (オブジェクト複製) | 4箇所 | 中 |
| A20 | `Hash.new(default)` | 2箇所 | 中 |

**Phase B: クラスシステム拡張**

| # | 機能 | lrama使用数 | 難易度 |
|---|------|------------|--------|
| B1 | `class X < Struct.new(...)` + メソッド追加 | 10クラス | 中 |
| B2 | `attr_writer` | 2箇所 | 低 |
| B3 | `Comparable` mixin (include + <=>) | 1箇所 | 低 |
| B4 | `extend Forwardable` + `def_delegators` | 5クラス | 高 |

**Phase C: 外部ライブラリ依存**

| # | 機能 | 難易度 | 備考 |
|---|------|--------|------|
| C1 | `StringScanner` | 高 | lexer.rb の根幹、自前実装必要 |
| C2 | `ERB` テンプレート | 高 | output.rb の根幹 |
| C3 | `OptionParser` | 高 | CLI解析、書き直し可能 |
| C4 | `Set` | 中 | sp_IntSet で代替可能 |

**Phase D: 動的機能 (コンパイル困難)**

| # | 機能 | 備考 |
|---|------|------|
| D1 | `module_eval` / `class_eval` | parser.rb (Racc生成) で使用 |
| D2 | `__send__` (動的ディスパッチ) | parser.rb で使用 |
| D3 | `define_method` / `respond_to_missing?` | 未使用 |

#### 進捗

**Phase A: 18/20 完了** ✅ (A17 group_by 後回し)
- A1-A16, A18-A20 全て実装済み
- A10 transform_values, A11 .to_h, A18 zip も完了

**Phase B: 3/4 完了** ✅
- B1 class < Struct.new ✅, B2 attr_writer ✅, B3 Comparable ✅
- B4 Forwardable → stub で回避

**追加実装:**
- `--lib=DIR` search path for `require` (stub system)
- Module::Class.new 構文
- nested class/module detection in modules
- module origin_parser (multi-file AST parser tracking)
- class/module dedup (再オープン対応)
- PM_RETURN_NODE / PM_UNLESS_NODE as expression
- PM_INSTANCE_VARIABLE_OR_WRITE_NODE (`@var ||=`)
- Array#<< on IntArray → sp_IntArray_push
- Array#map!, Array#insert
- Kernel#warn, report_duration stub
- type inference: OBJECT receiver method dispatch
- type inference: ivar name → class heuristic
- type inference: reopened class merging

**現状: lrama 71ファイル → 4500行 C 生成成功、395 warnings 残**

lrama ソース: `/home/matz/work/lrama/` (Spinel 対応修正はここで行う)

#### 今後のロードマップ

**Step 3: 型推論の改善** (~395 warnings → 目標 <100)
- Struct keyword_init フィールドの型推論 (call site から)
- メソッドチェーン `obj.field.method` の段階的型解決
- Array/Hash 要素型追跡 (`@rules` が Array of Rule 等)
- メソッド戻り値型の body 解析改善

**Step 4: lrama ソースの Spinel 対応修正** (`/home/matz/work/lrama/`)
- parser.rb: Racc 生成コードを静的メソッドに変換、または手書き再帰下降に置換
- output.rb: ERB テンプレートを事前展開、または簡易テンプレートに置換
- OptionParser 依存の除去 (手書き CLI パーサーに置換)
- StringScanner 依存の最小化 (可能なら正規表現ベースに置換)
- Racc 対応のドロップも検討

**Step 5: StringScanner stub (C実装)**
- lib/strscan.rb (型定義) + lib/strscan.c (oniguruma ベース)
- scan, matched, eos?, getch, pos, check, peek, scan_until

**Step 6: C コンパイル通過 → 実行形式生成**

---

## ポリモーフィズム設計

### 方針: ハイブリッド型 + 3段階ディスパッチ

現在の**単相最適化を維持**しつつ、必要な箇所にのみ**ボックス化**を導入する。
ディスパッチは多相度に応じた3段階方式。

```
型推論の結果:
  変数が常に1つの型 → 現在通り: mrb_int, mrb_float, sp_Vec, etc. (アンボックス)
  変数が複数の型    → sp_RbValue (ボックス化タグ付きユニオン)
```

### sp_RbValue: NaN-boxed 8バイト値 (JSC方式, favor pointer)

```c
typedef uint64_t sp_RbValue;  // 8バイト

// レイアウト:
//   ポインタ:  0x0000_XXXX_XXXX_XXX0  抽出: (void *)v          コスト: ゼロ
//   Integer:   0x0001_XXXX_XXXX_XXXX  抽出: 符号拡張48ビット    コスト: shift+extend
//   Double:    元のdoubleビット + 2^49                           コスト: 減算1回
//   Bool:      0x0002_0000_0000_000{0,1}
//   Nil:       0x0003_0000_0000_0000
//   クラスタグ: 0x0004+N (class_id encoded)
```

### 3段階メソッドディスパッチ

| 多相度 | 名称 | 方式 | 速度 |
|--------|------|------|------|
| 1型 | **monomorphic** | 直接呼び出し (現行) | 最速 |
| 2型 | **bimorphic** | call-site inline switch | 高速 |
| 3型以上 | **megamorphic** | dispatch関数 | 中速 |

### 実装ロードマップ (全完了)

| Phase | 内容 | 状態 |
|-------|------|------|
| **1** | sp_RbValue型定義 + boxing/unboxing + 基本演算 | ✅ |
| **2** | 異種配列 + bimorphicダックタイピング + 異種Hash | ✅ |
| **3** | パターンマッチ `case/in` | ✅ |
| **4** | megamorphic dispatch関数生成 | ✅ |
| **5** | sp_String (ミュータブル文字列 + GC) | ✅ |
| **6** | require_relative (複数ファイルコンパイル) | ✅ |
| **7** | NaN-boxing (8バイト化, favor pointer) | ✅ |

---

## プロジェクト構成

```
spinel/
├── src/
│   ├── main.c        # CLI、ファイル読み込み、Prismパース
│   ├── codegen.h     # 型システム、構造体定義、共有関数宣言
│   ├── codegen.c     # オーケストレータ、ユーティリティ、クラス解析、ラムダ、require
│   ├── type.c        # 型推論、型解決
│   ├── expr.c        # 式コード生成
│   ├── stmt.c        # 文コード生成
│   └── emit.c        # Cコード出力 (ヘッダ、構造体、メソッド)
├── examples/         # 54テストプログラム (53自動テスト)
├── prototype/
│   └── tools/        # Step 0プロトタイプ (RBS抽出、LumiTrace等)
├── Makefile
├── PLAN.md           # 本文書
└── ruby_aot_compiler_design.md  # 詳細設計文書
```

## ビルドフロー

```bash
make deps && make         # コンパイラビルド
./spinel --source=app.rb --output=app.c
cc -O2 app.c -lm -o app  # Regexp使用時は -lonig 追加
make test-all             # 53テスト実行
```

## 参考情報

- 詳細設計: `ruby_aot_compiler_design.md`
- プロトタイプツール: `prototype/`
- 参考実装: Crystal, TruffleRuby, Sorbet, mruby
