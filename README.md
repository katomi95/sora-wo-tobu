# そらをとぶ

**遊べるURL：https://katomi95.github.io/sora-wo-tobu/**

夕暮れの高層ビル屋上。疲れ切った中年会社員が、縁に立つ。
3〜5分の3D短編（Godot 4.7 / GL Compatibility / Web対応）。

## 操作
- 屋上：WASD / 矢印キーで歩く、縁で Space「飛ぶ」
- 飛行：W 前へ、A / D 曲がる、Space 上昇、Shift（または C / Ctrl）下降
- M：ミュート
- 画面右下に自宅までの距離、自宅のベランダの上に「自宅 ▼」

## 構成
- 導入（不穏）：背中越しの夕焼け → 横顔とため息 → 縁から見下ろす → 操作開始。フェンスが途切れた所まで歩く
- 「飛ぶ」：パラペットに上がる → 無音 →「お先失礼します〜」→ 落ちずにそのまま水平に滑り出す
- 帰宅飛行：進むほど夕方から夜になる。道中の出来事
  - まだ部長がいる階（「あ、まだ部長いる」）／ビル風に流される（「今日は風あるなあ」）
  - 鳥の群れが横切る（ぶつかると「おっと」）／スクランブル交差点の信号待ち
  - 川を渡ると遠くで踏切／スーパー（「スーパー寄ってくか」「……いや、いいか」）
  - 洗濯物のマンション（「明日雨か……」）／遠くのヘリと飛行機／ときどき独り言
- 着地：ベランダに普通に降りる →「ただいまー」「おかえり。今日遅かったね」「ちょっと向かい風強くて」→ 暗転
- なぜ飛べるのかは一切説明しない

## 素材
- モデル・街・空・効果音・BGM はすべてスクリプトで生成（外部素材なし、旋律もオリジナル）
  - 音：`tools/gen_audio.py`（風・街・ため息・羽ばたき・信号・ヘリ・踏切・サッシ・導入の重い曲・帰り道の曲）
  - 声は入れていない（台詞は字幕のみ）
- フォント：Noto Sans JP / Noto Serif JP（OFL）を `tools/make_font.py` でサブセット化

## 開発メモ
- 文言を変えたら `py -3.10 tools/make_font.py`（文字化け防止）
- 解析チェック：`bash tools/check.sh`
- 通しテスト：`godot --headless --path . --fixed-fps 60 -- --autoplay --fast=4 --mute --quit`（約170秒で ENDING REACHED）
- 撮影：`godot --path . --fixed-fps 60 -- --autoplay --fast=2 --shots=shots/x --at=13,29,40 --quit`
- 途中から：`--phase=walk|fly|end`、`--pos=x,y,z --head=度`、`--tod=0..1`（0=夕焼け 1=夜）
- Web書き出し：`godot --headless --path . --export-release Web docs/index.html`
