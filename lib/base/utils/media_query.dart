import 'package:flutter/material.dart';

bool isTooNarrow(BuildContext context) {
  return MediaQuery.widthOf(context) < 800;
}

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

/// 底部需要预留的高度：优先用系统 insets；车机投屏时 dock 由车载桌面绘制在
/// 应用窗口之上、insets 为 0，此时按屏幕高度比例预留，避免控件被 dock 遮挡。
double getBottomReserve(BuildContext context) {
  final mq = MediaQuery.of(context);
  final systemInset = mq.padding.bottom + mq.viewInsets.bottom;
  if (systemInset > 0) {
    return systemInset;
  }
  if (isCarProjection(context)) {
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
