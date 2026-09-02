import 'dart:math';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/utils/dynamic_lyrics_page_route.dart';
import 'package:sylvakru/base/widgets/audio_output_panel.dart';
import 'package:sylvakru/base/widgets/blurred_cover_art_widget.dart';
import 'package:sylvakru/base/widgets/buttons.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/widgets/my_divider.dart';
import 'package:sylvakru/base/widgets/playlist_widgets.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/portrait_view/sleep_timer.dart';
import 'package:sylvakru/base/widgets/my_sheet.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/base/widgets/lyric_list_view.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/data/playlist.dart';
import 'package:sylvakru/base/widgets/seekbar.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:text_scroll/text_scroll.dart';

class PortraitLyricsPage extends StatefulWidget {
  const PortraitLyricsPage({super.key});

  @override
  State<PortraitLyricsPage> createState() => _PortraitLyricsPageState();
}

class _PortraitLyricsPageState extends State<PortraitLyricsPage> {
  final dragOffsetNotifier = ValueNotifier(0.0);

  final canDragNotifier = ValueNotifier(false);

  final draggingNotifier = ValueNotifier(false);

  int _animationDuration = 0;

  Timer? concealRouteTimer;

  final enableAllNotifier = ValueNotifier(Platform.isAndroid ? false : true);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(milliseconds: 500));
      if (Platform.isAndroid) {
        enableAllNotifier.value = true;
      }
      canDragNotifier.value = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.heightOf(context);

    return ValueListenableBuilder(
      valueListenable: canDragNotifier,
      builder: (context, value, child) {
        return GestureDetector(
          onVerticalDragStart: value
              ? (_) {
                  draggingNotifier.value = true;
                  concealRouteTimer?.cancel();
                  final route = ModalRoute.of(context);
                  if (route is DynamicLyricsPageRoute) {
                    route.revealRoutesBelow();
                  }
                }
              : null,
          onVerticalDragUpdate: value
              ? (details) {
                  _animationDuration = 0;
                  dragOffsetNotifier.value += details.delta.dy;
                  dragOffsetNotifier.value = dragOffsetNotifier.value.clamp(
                    0.0,
                    screenHeight,
                  );
                }
              : null,

          onVerticalDragEnd: value
              ? (details) {
                  double velocity = details.primaryVelocity ?? 0;

                  if (dragOffsetNotifier.value * 3 > screenHeight ||
                      velocity > 500) {
                    Navigator.pop(context);
                  } else {
                    _animationDuration = 250;
                    dragOffsetNotifier.value = 0.0;
                    concealRouteTimer = Timer(Duration(milliseconds: 250), () {
                      draggingNotifier.value = false;
                      final route = ModalRoute.of(context);
                      if (route is DynamicLyricsPageRoute) {
                        route.concealRoutesBelow();
                      }
                    });
                  }
                }
              : null,
          onVerticalDragCancel: value
              ? () {
                  _animationDuration = 250;
                  dragOffsetNotifier.value = 0.0;
                  concealRouteTimer = Timer(Duration(milliseconds: 250), () {
                    draggingNotifier.value = false;
                    final route = ModalRoute.of(context);
                    if (route is DynamicLyricsPageRoute) {
                      route.concealRoutesBelow();
                    }
                  });
                }
              : null,
          child: child,
        );
      },
      child: ValueListenableBuilder(
        valueListenable: dragOffsetNotifier,
        builder: (context, value, child) {
          return AnimatedContainer(
            duration: Duration(milliseconds: _animationDuration),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, value, 0),
            child: child,
          );
        },
        child: content(),
      ),
    );
  }

  Widget content() {
    return ValueListenableBuilder(
      valueListenable: currentSongNotifier,
      builder: (context, currentSong, child) {
        return AnnotatedRegion(
          value: lyricsPageForegroundColor.value.computeLuminance() > 0.5
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: ValueListenableBuilder(
            valueListenable: draggingNotifier,
            builder: (context, value, child) {
              return Material(
                color: Colors.transparent,
                shape: SmoothRectangleBorder(
                  smoothness: 1,
                  borderRadius: .circular(
                    value ? screenRadius?.topLeft ?? 0 : 0,
                  ),
                ),
                clipBehavior: value ? .antiAliasWithSaveLayer : .antiAlias,
                child: child,
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (lyricsPageThemeNotifier.value == .vivid) ...[
                  BlurredCoverArtWidget(
                    song: currentSong,
                    color: colorManager
                        .getSpecificLyricsPageCoverArtBaseColor(),
                    sigmaX: 30,
                    sigmaY: 30,
                  ),
                  RepaintBoundary(
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      color: currentCoverArtColor.withAlpha(180),
                    ),
                  ),
                ],
                Container(
                  color: lyricsPageBackgroundColor.value,
                  child: Column(
                    children: [
                      SizedBox(height: 60),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: SizedBox(
                          height: 36,
                          child: ValueListenableBuilder(
                            valueListenable: enableAllNotifier,
                            builder: (context, value, child) {
                              final data = getTitle(currentSong);
                              final textStyle = TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: lyricsPageHighlightTextColor.value,
                                overflow: .ellipsis,
                              );
                              if (!value) {
                                return Text(data, style: textStyle);
                              }
                              return TextScroll(
                                textAlign: .center,
                                getTitle(currentSong),
                                velocity: const Velocity(
                                  pixelsPerSecond: Offset(40, 0),
                                ),
                                style: textStyle,
                                intervalSpaces: 10,
                                pauseBetween: Duration(seconds: 1),
                              );
                            },
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: SizedBox(
                          height: 28,
                          child: ValueListenableBuilder(
                            valueListenable: enableAllNotifier,
                            builder: (context, value, child) {
                              final data =
                                  '${getArtist(currentSong)} - ${getAlbum(currentSong)}';
                              final textStyle = TextStyle(
                                fontSize: 14,
                                color: lyricsPageForegroundColor.value,
                                overflow: .ellipsis,
                              );
                              if (!value) {
                                return Text(data, style: textStyle);
                              }
                              return TextScroll(
                                textAlign: .center,
                                data,
                                velocity: const Velocity(
                                  pixelsPerSecond: Offset(40, 0),
                                ),
                                style: textStyle,
                                intervalSpaces: 10,
                                pauseBetween: Duration(seconds: 1),
                              );
                            },
                          ),
                        ),
                      ),
                      SizedBox(height: 10),

                      Expanded(
                        child: PageView(
                          children: [
                            artPage(context, currentSong),
                            ValueListenableBuilder(
                              valueListenable: enableAllNotifier,
                              builder: (context, value, child) {
                                if (!value) {
                                  return SizedBox.shrink();
                                }
                                return expandedLyricsPage(context, currentSong);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget artPage(BuildContext context, MyAudioMetadata? currentSong) {
    final l10n = AppLocalizations.of(context);
    final mobileWidth = MediaQuery.widthOf(context);

    // 自适应封面：按容器实际可用高度反推，先给底部控件区和歌词区留出下限，
    // 剩下的才给封面。这样任意分辨率/车机窗口都不会把控件挤出屏幕。
    return LayoutBuilder(
      builder: (context, constraints) {
        // 底部固定区实测高度：输出胶囊(约 46) + 功能按钮行(约 48) +
        // 进度条(60) + 播放控件行(约 56) + 间距(30 + 12) + dock 预留
        final bottomBlock =
            (isCarProjection(context) ? 234.0 : 252.0) +
            getBottomReserve(context);
        // 歌词区至少留这么高，否则封面会把歌词压没
        final minLyrics = isCarProjection(context) ? 56.0 : 120.0;
        final available = constraints.maxHeight - bottomBlock - minLyrics;
        final coverSize = max(
          80.0,
          min(mobileWidth * 0.62, available),
        );

        return artPageContent(context, currentSong, l10n, coverSize);
      },
    );
  }

  Widget artPageContent(
    BuildContext context,
    MyAudioMetadata? currentSong,
    AppLocalizations l10n,
    double coverSize,
  ) {
    // 车机投屏：左封面 + 右侧信息/控件的横向布局（窗口很矮，纵向堆叠放不下）
    if (isCarProjection(context)) {
      return carProjectionArtPage(context, currentSong, l10n, coverSize);
    }
    return Column(
      children: [
        Hero(
          tag: 'cover',
          flightShuttleBuilder:
              (
                flightContext,
                animation,
                flightDirection,
                fromHeroContext,
                toHeroContext,
              ) => FittedBox(child: toHeroContext.widget),
          child: CoverArtWidget(
            size: coverSize,
            borderRadius: coverSize * 0.05,
            song: currentSong,
            elevation: 15,
            color: colorManager.getSpecificLyricsPageCoverArtBaseColor(),
          ),
        ),

        SizedBox(height: isCarProjection(context) ? 12 : 30),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: ShaderMask(
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent, // fade out at top
                    Colors.grey.shade50, // fully visible
                    Colors.grey.shade50, // fully visible
                    Colors.transparent, // fade out at bottom
                  ],
                  stops: [0.0, 0.1, 0.8, 1.0], // adjust fade height
                ).createShader(rect);
              },
              blendMode: BlendMode.dstIn,
              // use key to force update
              child: currentSong == null
                  ? SizedBox()
                  : ValueListenableBuilder(
                      valueListenable: enableAllNotifier,
                      builder: (context, value, child) {
                        if (!value) {
                          return SizedBox.shrink();
                        }
                        return LyricsListView(
                          key: ValueKey(currentSong),
                          expanded: false,
                          lines: currentSong.parsedLyrics!.lines,
                          isKaraoke: currentSong.parsedLyrics!.isKaraoke,
                        );
                      },
                    ),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(34, 0, 34, 12),
          child: ValueListenableBuilder(
            valueListenable: lyricsPageForegroundColor.valueNotifier,
            builder: (context, value, child) {
              return AudioOutputChip(song: currentSong, color: value);
            },
          ),
        ),

        Row(
          children: [
            SizedBox(width: 25),
            FavoriteButton(),
            IconButton(
              color: lyricsPageForegroundColor.value,
              onPressed: () {
                displayTimedPauseSetting(context);
              },
              icon: ImageIcon(timerImage, size: 25),
            ),
            remainTimesText(textColor: lyricsPageForegroundColor.value),
            Spacer(),
            IconButton(
              color: lyricsPageForegroundColor.value,
              onPressed: () {
                lyricsFontSizeOffsetNotifier.value += 2;
                setting.save();
              },
              icon: Icon(Icons.text_increase_rounded),
            ),
            IconButton(
              color: lyricsPageForegroundColor.value,
              onPressed: () {
                if (lyricsFontSizeOffsetNotifier.value < -2) {
                  return;
                }
                lyricsFontSizeOffsetNotifier.value -= 2;
                setting.save();
              },
              icon: Icon(Icons.text_decrease_rounded),
            ),

            IconButton(
              onPressed: () {
                tryVibrate();
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) {
                    return MySheet(
                      ValueListenableBuilder(
                        valueListenable:
                            lyricsPageForegroundColor.valueNotifier,
                        builder: (context, value, child) {
                          return Column(
                            children: [
                              SizedBox(height: 5),

                              ListTile(
                                leading: CoverArtWidget(
                                  size: 50,
                                  borderRadius: 5,
                                  song: currentSong,
                                ),
                                title: Text(
                                  getTitle(currentSong),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: value),
                                ),
                                subtitle: Text(
                                  "${getArtist(currentSong)} - ${getAlbum(currentSong)}",
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: value),
                                ),
                              ),

                              SizedBox(height: 5),
                              MyDivider(
                                color: lyricsPageDividerColor,
                                thickness: 0.5,
                                height: 1,
                              ),
                              SizedBox(height: 5),

                              Expanded(
                                child: ListView(
                                  physics: const ClampingScrollPhysics(),
                                  children: [
                                    ListTile(
                                      leading: Icon(
                                        Icons.add_rounded,
                                        color: value,
                                      ),
                                      title: Text(
                                        l10n.add2Playlist,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: value,
                                        ),
                                      ),
                                      visualDensity: const VisualDensity(
                                        horizontal: 0,
                                        vertical: -4,
                                      ),
                                      onTap: () {
                                        Navigator.pop(context);

                                        showAddPlaylistDialog(context, [
                                          currentSong!,
                                        ]);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                );
              },
              icon: ValueListenableBuilder(
                valueListenable: lyricsPageForegroundColor.valueNotifier,
                builder: (context, value, child) {
                  return Icon(Icons.more_vert, color: value);
                },
              ),
            ),
            SizedBox(width: 25),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: ValueListenableBuilder(
            valueListenable: lyricsPageForegroundColor.valueNotifier,
            builder: (context, value, child) {
              return SeekBar(color: value, widgetHeight: 60, seekBarHeight: 40);
            },
          ),
        ),

        // -------- Play Controls --------
        ValueListenableBuilder(
          valueListenable: lyricsPageForegroundColor.valueNotifier,
          builder: (context, value, child) {
            return Row(
              children: [
                SizedBox(width: 25),

                playModeButton(32, iconColor: value),

                Spacer(),

                skip2PreviousButton(32, iconColor: value),

                Spacer(),

                playOrPauseButton(50, iconColor: value),

                Spacer(),

                skip2NextButton(32, iconColor: value),

                Spacer(),

                showPlayQueueButton(32, iconColor: value),

                SizedBox(width: 25),
              ],
            );
          },
        ),

        SizedBox(height: 40 + getBottomReserve(context)),
      ],
    );
  }

  /// 车机投屏播放页：左侧封面 + 右侧标题/控件的横向布局。
  /// 车机窗口宽而矮（如 880x768 可视区更矮），纵向堆叠会把控件挤出屏幕。
  Widget carProjectionArtPage(
    BuildContext context,
    MyAudioMetadata? currentSong,
    AppLocalizations l10n,
    double coverSize,
  ) {
    final width = MediaQuery.widthOf(context);
    final height = MediaQuery.heightOf(context) - getBottomReserve(context);
    final cover = min(width * 0.3, height * 0.62);

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, getBottomReserve(context) + 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Hero(
            tag: 'cover',
            flightShuttleBuilder:
                (
                  flightContext,
                  animation,
                  flightDirection,
                  fromHeroContext,
                  toHeroContext,
                ) => FittedBox(child: toHeroContext.widget),
            child: CoverArtWidget(
              size: cover,
              borderRadius: cover * 0.06,
              song: currentSong,
              elevation: 15,
              color: colorManager.getSpecificLyricsPageCoverArtBaseColor(),
            ),
          ),

          SizedBox(width: 28),

          Expanded(
            child: ValueListenableBuilder(
              valueListenable: lyricsPageForegroundColor.valueNotifier,
              builder: (context, fg, child) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      getTitle(currentSong),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: fg,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      getArtist(currentSong),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: fg.withAlpha(200)),
                    ),

                    SizedBox(height: 14),

                    // 收藏 / 定时 / 播放列表
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        FavoriteButton(size: 26),
                        IconButton(
                          color: fg,
                          onPressed: () {
                            displayTimedPauseSetting(context);
                          },
                          icon: ImageIcon(timerImage, size: 24),
                        ),
                        showPlayQueueButton(26, iconColor: fg),
                      ],
                    ),

                    SeekBar(color: fg, widgetHeight: 44, seekBarHeight: 28),

                    // 播放控件
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        playModeButton(26, iconColor: fg),
                        skip2PreviousButton(30, iconColor: fg),
                        playOrPauseButton(44, iconColor: fg),
                        skip2NextButton(30, iconColor: fg),
                        IconButton(
                          color: fg,
                          onPressed: () {
                            lyricsFontSizeOffsetNotifier.value += 2;
                            setting.save();
                          },
                          icon: Icon(Icons.text_increase_rounded, size: 24),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget expandedLyricsPage(
    BuildContext context,
    MyAudioMetadata? currentSong,
  ) {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: ShaderMask(
                shaderCallback: (rect) {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent, // fade out at top
                      Colors.grey.shade50, // fully visible
                      Colors.grey.shade50, // fully visible
                      Colors.transparent, // fade out at bottom
                    ],
                    stops: [0.0, 0.1, 0.7, 1.0], // adjust fade height
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: currentSong == null
                    ? SizedBox()
                    : LyricsListView(
                        key: ValueKey(currentSong),
                        expanded: true,
                        lines: currentSong.parsedLyrics!.lines,
                        isKaraoke: currentSong.parsedLyrics!.isKaraoke,
                      ),
              ),
            ),
            SizedBox(height: 50),
          ],
        ),

        Positioned(
          right: 25,
          bottom: 40,
          child: ValueListenableBuilder(
            valueListenable: lyricsPageForegroundColor.valueNotifier,
            builder: (context, value, child) {
              return IconButton(
                color: value,
                icon: ValueListenableBuilder(
                  valueListenable: isPlayingNotifier,
                  builder: (_, isPlaying, _) {
                    return Icon(
                      isPlaying
                          ? Icons.pause_circle_rounded
                          : Icons.play_circle_rounded,
                      size: 48,
                    );
                  },
                ),
                onPressed: () => audioHandler.togglePlay(),
              );
            },
          ),
        ),
      ],
    );
  }
}

class FavoriteButton extends StatelessWidget {
  final double? size;
  const FavoriteButton({super.key, this.size});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: currentSongNotifier,
      builder: (_, currentSong, _) {
        if (currentSong == null) return SizedBox();
        return ValueListenableBuilder(
          valueListenable: currentSong.isFavoriteNotifier,
          builder: (_, value, _) {
            return IconButton(
              onPressed: () {
                tryVibrate();
                toggleFavoriteState(currentSong);
              },
              icon: ValueListenableBuilder(
                valueListenable: lyricsPageForegroundColor.valueNotifier,
                builder: (context, color, child) {
                  return Icon(
                    value ? Icons.favorite : Icons.favorite_outline,
                    color: value ? Colors.red : color,
                    size: size,
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
