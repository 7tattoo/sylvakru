import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool isTooNarrow(BuildContext context) {
  return MediaQuery.widthOf(context) < 800;
}

/// 原生侧探测结果（MainActivity.windowMetrics）：应用窗口底边已高于物理屏幕
/// 底边 → 车联 dock 被系统排在应用窗口之外，窗口内不需要再按比例预留空间。
/// 探测失败/未探测时保持 false，退回 16% 兜底（安全默认）。
final ValueNotifier<bool> windowAboveDockNotifier = ValueNotifier(false);

/// 车机投屏检测：车机窗口是横向但很"矮"（宽高比远小于手机横屏的 ~2.0），
/// 例如 880x768 → 1.15。手机竖屏被 width > height 排除，平板横屏
/// （1280x800 = 1.6）也被阈值排除。
bool isCarProjection(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (size.width <= size.height) {
    return false;
  }
  return size.width / size.height < 1.6;
}

/// 底部需要预留的高度：优先用系统 insets；车机投屏且 dock 直接绘制在应用窗口
/// 之上时（insets 为 0）按屏幕高度比例预留；若原生探测到窗口底边已高于屏幕
/// 底边（dock 在窗口之外），则不留兜底，内容贴到窗口底（自适应车机 dock 高度）。
double getBottomReserve(BuildContext context) {
  final mq = MediaQuery.of(context);
  final systemInset = mq.padding.bottom + mq.viewInsets.bottom;
  if (systemInset > 0) {
    return systemInset;
  }
  if (isCarProjection(context) && !windowAboveDockNotifier.value) {
    return mq.size.height * 0.16;
  }
  return 0;
}

double getTopOffset(BuildContext context) {
  final topPadding = MediaQuery.of(context).padding.top;
  if (topPadding >= 20) {
    return topPadding - 20;
  }
  return 0;
}
