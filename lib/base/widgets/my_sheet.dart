import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:smooth_corner/smooth_corner.dart';

class MySheet extends StatelessWidget {
  final Widget child;
  final double? height;

  const MySheet(this.child, {super.key, this.height});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: currentSongNotifier,
      builder: (context, _, _) {
        // 车机 dock 覆盖在应用窗口之上（系统 insets 为 0），bottom sheet 必须
        // 自行预留，否则底部选项被 dock 挡住点不到。
        final bottomReserve = getBottomReserve(context);
        final pageHeight = MediaQuery.heightOf(context);
        final maxSheetHeight = pageHeight - bottomReserve - 24;
        final sheetHeight = min(
          height ?? min(500.0, pageHeight * 0.6),
          maxSheetHeight,
        );

        return Material(
          shape: SmoothRectangleBorder(
            smoothness: 1,
            borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
          ),
          color: Color.alphaBlend(
            colorManager.getSpecificBgColor(),
            colorManager.getSpecificBgBaseColor(),
          ),
          clipBehavior: .antiAlias,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomReserve),
            child: SizedBox(
              height: sheetHeight,
              child: MediaQuery.removePadding(
                context: context,
                removeLeft: true, // for mobile
                removeRight: true,
                removeBottom: true,
                removeTop: true,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
