# 语音与视觉模型

## 语音输入

当前 UI 已接入 Live / 语音输入的交互状态，识别后端仍是占位：

- 移动端：长按输入框进入语音态
- 桌面端：输入框未聚焦时空格进入语音态，Esc 退出
- Live：长按发送键或空输入按 Enter 进入，Esc / 点击旋转后的叉号退出

### 推荐模型

1. **X-ASR-zh-en 480ms streaming zipformer transducer**
   - 中英混合、带标点、流式、int8
   - 约 134 MB
   - 模型：`https://www.modelscope.cn/models/adaada88/sherpa-onnx-x-asr-480ms-streaming-zipformer-transducer-zh-en-punct-int8`
   - 推理需要 sherpa-onnx / zipformer2 运行时；Xime 使用自研 `libasr_jni.so`
   - 参考实现：`https://github.com/ximeiorg/Xime`（GPL-3.0，集成前确认模型与代码许可）

2. **Whisper tiny / base**
   - whisper.cpp 可直接在端侧运行，tiny 约 75 MB、base 约 142 MB
   - 英文/多语言好，中文标点弱于 X-ASR
   - 适合桌面端或离线兜底

建议路线：先接 X-ASR 流式模型作为主 ASR，Whisper tiny 作为英文/兜底；模型放 support 目录，按需下载，避免 APK 体积。

## YOLO 视觉

顶栏左侧眼睛按钮已预留，当前点击只提示“即将接入”。

移动端推荐：
- YOLO11n / YOLOv8n（约 2.6M 参数，TFLite/ONNX int8 约 3–7 MB）
- 输入 320/416，CPU int8 可在中端机实时运行
- 可接 `tflite_flutter`（Android/Linux/Windows）或 ONNX Runtime Mobile

用途：画面主体识别、人物/物品定位，后续把检测结果作为视觉上下文注入对话，而不是直接上传整张图。

## 当前状态

- Stage、顶栏抽屉、台词卡、Live 动效已实现
- ASR/YOLO 推理尚未打包；UI 和模型路线已预留
