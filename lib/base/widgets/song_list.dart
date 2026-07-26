import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/data/song_list_manager.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/services/keyboard.dart';
import 'package:sylvakru/base/utils/format_duration.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/utils/source_type.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/data/folder.dart';
import 'package:sylvakru/base/data/history.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/data/playlist.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/base/widgets/edit_metadata.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/widgets/my_divider.dart';
import 'package:sylvakru/base/widgets/my_location.dart';
import 'package:sylvakru/base/widgets/my_sheet.dart';
import 'package:sylvakru/base/widgets/my_switch.dart';
import 'package:sylvakru/base/widgets/playlist_widgets.dart';
import 'package:sylvakru/base/widgets/selectable_song_list_page.dart';
import 'package:sylvakru/base/widgets/song_info.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/landscape_view/title_bar.dart';
import 'package:sylvakru/layer/albums_layer.dart';
import 'package:sylvakru/layer/artists_layer.dart';
import 'package:sylvakru/layer/folders_layer.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/layer/playlists_layer.dart';
import 'package:sylvakru/portrait_view/custom_appbar_leading.dart';
import 'package:sylvakru/portrait_view/my_search_field.dart';
import 'package:sylvakru/portrait_view/song_list_tile.dart';
import 'package:text_scroll/text_scroll.dart';

part '../../landscape_view/panels/song_list_panel.dart';
part '../../portrait_view/pages/song_list_page.dart';

class SongList extends StatefulWidget {
  final Playlist? playlist;
  final Artist? artist;
  final Album? album;
  final Folder? folder;
  final bool isRanking;
  final bool isRecently;

  final bool isRoot;

  final SourceType sourceType;

  final Function(BuildContext)? switchCallBack;

  const SongList({
    super.key,
    this.playlist,
    this.artist,
    this.album,
    this.folder,
    this.isRanking = false,
    this.isRecently = false,
    this.isRoot = true,
    this.sourceType = .local,
    this.switchCallBack,
  });

  @override
  State<StatefulWidget> createState() => _SongListState();
}

class _SongListState extends State<SongList> {
  String title = '';
  late SongListManager songListManager;
  late List<MyAudioMetadata> songList;
  Playlist? playlist;
  Artist? artist;
  Album? album;
  Folder? folder;

  bool isLibrary = false;
  bool isRanking = false;
  bool isRecently = false;

  bool reorderable = false;

  late SourceType sourceType;

  Timer? timer;

  bool waitForSecondClick = false;
  Timer? doubleClicktimer;

  final currentSongListNotifier = ValueNotifier<List<MyAudioMetadata>>([]);

  // 专辑结构显示行：>=0 为 currentSongList 中的歌曲索引，
  // 负值 -(i+1) 表示从歌曲索引 i 开始的一段专辑的专辑头；
  // 收起的专辑不含歌曲行，行高统一 60，供定位换算使用
  List<int> albumStructureRows = [];
  // 各专辑段首曲在 currentSongList 中的索引（含收起的专辑），供分组渲染使用
  List<int> albumGroupStarts = [];
  // 专辑结构模式中被收起的专辑
  final collapsedAlbums = <String>{};

  final listIsScrollingNotifier = ValueNotifier(false);
  final scrollController = ScrollController();
  final textController = TextEditingController();

  ValueNotifier<int> sortTypeNotifier = ValueNotifier(0);

  List<ValueNotifier<bool>> isSelectedList = [];
  bool isFixed = false;
  int continuousSelectBeginIndex = 0;

  final showPlayButtonNotifierMap = <MyAudioMetadata, ValueNotifier<bool>>{};

  final padding = const EdgeInsets.symmetric(horizontal: 30);

  final isSearchNotifier = ValueNotifier(false);

  ValueNotifier<bool>? rootVisibleNotifier;
  Function()? backToRoot;

  bool hideOthers = false;

  String rootLabel = '';

  void updateHideOthers() {
    setState(() {
      hideOthers = rootVisibleNotifier!.value;
    });
  }

  String getTitleText(AppLocalizations l10n) {
    return isLibrary
        ? l10n.songs
        : playlist?.isFavorite == true
        ? l10n.favorites
        : isRanking
        ? l10n.ranking
        : isRecently
        ? l10n.recently
        : title;
  }

  // 歌单与所有歌曲页支持专辑结构显示，开关各自全局记忆
  bool get albumStructureSupported => playlist != null || isLibrary;

  ValueNotifier<bool> get albumStructureNotifier => playlist != null
      ? playlistManager.useAlbumStructureNotifier
      : library.useAlbumStructureNotifier;

  bool get albumStructureActive =>
      albumStructureSupported && albumStructureNotifier.value;

  void updateSongList() {
    final value = textController.text;
    final filteredSongList = filterSongList(songList, value);
    if (albumStructureActive) {
      // 专辑结构固定按专辑升序排列，专辑内按碟号/音轨号
      sortSongList(5, filteredSongList);
    } else {
      sortSongList(sortTypeNotifier.value, filteredSongList);
    }

    albumStructureRows = [];
    albumGroupStarts = [];
    if (albumStructureActive) {
      String? lastAlbum;
      for (int i = 0; i < filteredSongList.length; i++) {
        final album = getAlbum(filteredSongList[i]);
        if (album != lastAlbum) {
          lastAlbum = album;
          albumGroupStarts.add(i);
          albumStructureRows.add(-i - 1);
        }
        if (!collapsedAlbums.contains(album)) {
          albumStructureRows.add(i);
        }
      }
    }
    currentSongListNotifier.value = filteredSongList;

    isSelectedList = List.generate(
      filteredSongList.length,
      (_) => ValueNotifier(false),
    );
    isFixed =
        isMobile ||
        !reorderable ||
        textController.text.isNotEmpty ||
        sortTypeNotifier.value > 0 ||
        albumStructureActive;

    continuousSelectBeginIndex = 0;

    showPlayButtonNotifierMap.clear();
    for (var e in filteredSongList) {
      showPlayButtonNotifierMap[e] = ValueNotifier(false);
    }
  }

  @override
  void initState() {
    super.initState();

    playlist = widget.playlist;
    artist = widget.artist;
    album = widget.album;
    folder = widget.folder;
    isRanking = widget.isRanking;
    isRecently = widget.isRecently;

    sourceType = widget.sourceType;

    if (playlist != null) {
      title = playlist!.name;
      songListManager = playlist!.songListManager;
      reorderable = true;
      if (!widget.isRoot) {
        rootVisibleNotifier = playlistsVisibleNotifier;
        backToRoot = () {
          layersManager.popDetail('playlists');
        };
        rootLabel = 'playlists';
      }
    } else if (artist != null) {
      title = artist!.name;
      songListManager = artist!.songListManager;
      rootVisibleNotifier = artistsVisibleNotifier;
      backToRoot = () {
        layersManager.popDetail('artists');
      };
      rootLabel = 'artists';
    } else if (album != null) {
      title = album!.name;
      songListManager = album!.songListManager;
      rootVisibleNotifier = albumsVisibleNotifier;
      backToRoot = () {
        layersManager.popDetail('albums');
      };
      rootLabel = 'albums';
    } else if (folder != null) {
      title = folder!.id;
      reorderable = true;
      rootVisibleNotifier = foldersVisibleNotifier;
      backToRoot = () {
        layersManager.popDetail('folders');
      };
      rootLabel = 'folders';
    } else if (isRanking) {
      songListManager = history.rankingSongListManager;
    } else if (isRecently) {
      songListManager = history.recentlySongListManager;
    } else {
      isLibrary = true;
      songListManager = library.songListManager;
      reorderable = sourceType == .local || sourceType == .webdav;
    }
    if (folder == null) {
      songList = songListManager.getSongList2(sourceType);
      sortTypeNotifier = songListManager.getSortTypeNotifier2(sourceType);
      songListManager
          .getChangeNotifier2(sourceType)
          .addListener(updateSongList);
    } else {
      songList = folder!.songList;
      sortTypeNotifier = folder!.sortTypeNotifier;
      folder!.changeNotifier.addListener(updateSongList);
    }
    rootVisibleNotifier?.addListener(updateHideOthers);

    if (albumStructureSupported) {
      albumStructureNotifier.addListener(updateSongList);
    }

    updateSongList();
    sortTypeNotifier.addListener(updateSongList);
    textController.addListener(updateSongList);
  }

  // 当前播放歌曲是否属于该专辑段（用于专辑头高亮）
  bool albumStructureGroupIsPlaying(String album) {
    final current = currentSongNotifier.value;
    return current != null &&
        getAlbum(current) == album &&
        currentSongListNotifier.value.contains(current);
  }

  // 收起/展开专辑段
  void toggleAlbumCollapsed(String album) {
    if (!collapsedAlbums.remove(album)) {
      collapsedAlbums.add(album);
    }
    updateSongList();
  }

  // 是否已全部收起（显示行中不再有歌曲行）
  bool get allAlbumsCollapsed =>
      albumStructureRows.isNotEmpty &&
      albumStructureRows.every((row) => row < 0);

  // 一键全部收起/展开
  void setAllAlbumsCollapsed(bool collapsed) {
    collapsedAlbums.clear();
    if (collapsed) {
      for (final song in currentSongListNotifier.value) {
        collapsedAlbums.add(getAlbum(song));
      }
    }
    updateSongList();
  }

  // 歌曲在专辑结构列表中的显示行；被收起时退回其专辑头所在行
  int albumStructureDisplayIndex(int index) {
    final display = albumStructureRows.indexOf(index);
    if (display != -1) {
      return display;
    }
    final list = currentSongListNotifier.value;
    final album = getAlbum(list[index]);
    for (int i = 0; i < albumStructureRows.length; i++) {
      final row = albumStructureRows[i];
      if (row < 0 && getAlbum(list[-row - 1]) == album) {
        return i;
      }
    }
    return 0;
  }

  // 专辑头对应专辑段的歌曲数（start 为该段首曲在 currentSongList 中的索引）
  int albumStructureGroupCount(int start) {
    final list = currentSongListNotifier.value;
    final album = getAlbum(list[start]);
    int end = start + 1;
    while (end < list.length && getAlbum(list[end]) == album) {
      end++;
    }
    return end - start;
  }

  @override
  void dispose() {
    if (folder == null) {
      songListManager
          .getChangeNotifier2(sourceType)
          .removeListener(updateSongList);
    } else {
      folder!.changeNotifier.removeListener(updateSongList);
    }

    rootVisibleNotifier?.removeListener(updateHideOthers);

    if (albumStructureSupported) {
      albumStructureNotifier.removeListener(updateSongList);
    }

    sortTypeNotifier.removeListener(updateSongList);
    textController.removeListener(updateSongList);
    scrollController.dispose();
    timer?.cancel();
    doubleClicktimer?.cancel();
    super.dispose();
  }

  Widget mainCover(double size) {
    return ValueListenableBuilder(
      valueListenable: currentSongListNotifier,
      builder: (_, _, _) {
        final song = getFirstSong(songList);
        return ListenableBuilder(
          listenable: Listenable.merge([song?.updateNotifier]),
          builder: (_, _) {
            return ValueListenableBuilder(
              valueListenable: mainPageThemeNotifier,
              builder: (_, _, _) {
                final coverArt = CoverArtWidget(
                  size: size,
                  borderRadius: size / 10,
                  song: song,
                  elevation: 5,
                  color: colorManager.getSpecificMainPageCoverArtBaseColorForm(
                    song,
                  ), // keep stable color
                );
                return widget.isRoot
                    ? coverArt
                    : Hero(
                        tag: (song == null ? sourceType.name : song.id) + title,
                        transitionOnUserGestures: true,
                        child: coverArt,
                      );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isTooNarrow(context)) {
      return pageView(context);
    }
    return panelView(context);
  }
}
