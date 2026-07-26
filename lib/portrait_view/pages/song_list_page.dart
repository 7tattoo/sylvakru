part of '../../base/widgets/song_list.dart';

extension _SongListPage on _SongListState {
  Widget pageView(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          customAppBar(context),
          Expanded(child: contentWithStack()),
        ],
      ),
    );
  }

  PreferredSizeWidget customAppBar(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: customAppBarLeading(context, label: rootLabel),
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      systemOverlayStyle: mainPageThemeNotifier.value == .dark ? .light : .dark,
      actions: [
        ValueListenableBuilder(
          valueListenable: currentSongListNotifier,
          builder: (context, value, child) {
            return MySearchField(
              key: ValueKey(getFirstSong(songList)),
              hintText: AppLocalizations.of(context).searchSongs,
              textController: textController,
              isSearchNotifier: isSearchNotifier,
              song: getFirstSong(songList),
              useCurrentSong: false,
            );
          },
        ),
        moreButton(context),
      ],
    );
  }

  Widget moreButton(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.more_vert),
      onPressed: () {
        tryVibrate();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          builder: (context) {
            return moreSheet(context);
          },
        ).then((value) {
          if (value == true && context.mounted) {
            Navigator.pop(context);
          }
        });
      },
    );
  }

  Widget moreSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return MySheet(
      Column(
        children: [
          ListTile(
            title: SizedBox(
              height: 40,
              width: MediaQuery.widthOf(context) * 0.9,
              child: Row(
                children: [
                  if (playlist != null)
                    Text("${l10n.playlists}: ", style: TextStyle(fontSize: 15)),
                  if (artist != null)
                    Text("${l10n.artists}: ", style: TextStyle(fontSize: 15)),
                  if (album != null)
                    Text("${l10n.albums}: ", style: TextStyle(fontSize: 15)),
                  if (folder != null)
                    Text("${l10n.folders}: ", style: TextStyle(fontSize: 15)),

                  Expanded(
                    child: TextScroll(
                      getTitleText(l10n),
                      style: TextStyle(fontSize: 15),
                      velocity: const .new(pixelsPerSecond: .new(40, 0)),
                      intervalSpaces: 10,
                      pauseBetween: Duration(seconds: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          MyDivider(thickness: 0.5, height: 1, color: dividerColor),
          ListTile(
            leading: ImageIcon(selectImage),
            title: Text(
              l10n.select,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SelectableSongListPage(
                    songList: songList,
                    playlist: playlist,
                    folder: folder,
                    isRanking: isRanking,
                    isRecently: isRecently,
                    isLibrary: isLibrary,
                    reorderable: reorderable,
                  ),
                ),
              );
            },
          ),
          if (playlist != null)
            ListTile(
              leading: ValueListenableBuilder(
                valueListenable: playlistManager.useAlbumStructureNotifier,
                builder: (context, value, child) {
                  return ImageIcon(value ? albumImage : listImage);
                },
              ),
              title: Text(
                l10n.view,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
              trailing: SizedBox(
                width: 100,
                child: Row(
                  children: [
                    Spacer(),
                    MySwitch(
                      trueText: l10n.albums,
                      falseText: l10n.list,
                      valueNotifier: playlistManager.useAlbumStructureNotifier,
                      onToggleCallBack: () {
                        setting.save();
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (!isRanking && !isRecently)
            ValueListenableBuilder(
              valueListenable: playlistManager.useAlbumStructureNotifier,
              builder: (context, value, child) {
                // 专辑结构模式固定按专辑排序，隐藏歌曲排序入口
                if (albumStructureActive) {
                  return SizedBox.shrink();
                }
                return child!;
              },
              child: ListTile(
                leading: ImageIcon(sequenceImage),
                title: Text(
                  l10n.sortSongs,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useRootNavigator: true,
                    builder: (context) {
                      List<String> orderText = [
                        l10n.defaultText,
                        l10n.titleAscending,
                        l10n.titleDescending,
                        l10n.artistAscending,
                        l10n.artistDescending,
                        l10n.albumAscending,
                        l10n.albumDescending,
                        l10n.durationAscending,
                        l10n.durationDescending,
                      ];
                      if (isLibrary &&
                              (sourceType == .local || sourceType == .webdav) ||
                          folder != null) {
                        orderText.add(l10n.modifiedTimeAscending);
                        orderText.add(l10n.modifiedTimedescending);
                        orderText.add(l10n.randomizeTemp);
                        orderText.add(l10n.randomizePermanent);
                      }
                      List<Widget> orderWidget = [];
                      for (int i = 0; i < orderText.length; i++) {
                        String text = orderText[i];
                        orderWidget.add(
                          ValueListenableBuilder(
                            valueListenable: sortTypeNotifier,
                            builder: (context, value, child) {
                              return ListTile(
                                title: Text(text),
                                onTap: () async {
                                  if (i == 12) {
                                    if (!await showConfirmDialog(
                                      context,
                                      l10n.cannotBeUndone,
                                    )) {
                                      return;
                                    }
                                    sortTypeNotifier.value = 0;
                                    if (isLibrary) {
                                      library.shuffle(sourceType);
                                    } else {
                                      folder!.shuffle();
                                    }
                                  } else {
                                    if (i == 11 &&
                                        sortTypeNotifier.value == 11) {
                                      updateSongList();
                                    }
                                    sortTypeNotifier.value = i;

                                    playlist?.saveSetting();
                                  }
                                },
                                trailing: value == i ? Icon(Icons.check) : null,
                                visualDensity: VisualDensity(
                                  horizontal: 0,
                                  vertical: -4,
                                ),
                              );
                            },
                          ),
                        );
                      }
                      return MySheet(
                        Column(
                          children: [
                            ListTile(title: Text(l10n.selectSortingType)),
                            MyDivider(
                              thickness: 0.5,
                              height: 1,
                              color: dividerColor,
                            ),

                            Expanded(
                              child: ListView(
                                children: [
                                  ...orderWidget,
                                  SizedBox(height: 50),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

          if (folder == null)
            ValueListenableBuilder(
              valueListenable: songListManager.changeNotifier,
              builder: (context, value, child) {
                if (songListManager.notEmptyCount < 2) {
                  return SizedBox.shrink();
                }
                return ListTile(
                  leading: ImageIcon(serverImage),
                  title: Text(
                    l10n.switch_,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  visualDensity: const VisualDensity(
                    horizontal: 0,
                    vertical: -4,
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    widget.switchCallBack!(context);
                  },
                );
              },
            ),
          if (playlist != null && playlist!.isNotFavorite)
            ListTile(
              leading: ImageIcon(deleteImage),
              title: Text(
                l10n.delete,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
              onTap: () async {
                if (await showConfirmDialog(context, l10n.delete)) {
                  layersManager.removeLayerIfNeed(playlist!);
                  playlistManager.deletePlaylist(playlist!);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }
              },
            ),
        ],
      ),
    );
  }

  Widget contentWithStack() {
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle) {
              listIsScrollingNotifier.value = true;
              if (timer != null) {
                timer!.cancel();
                timer = null;
              }
            } else {
              if (listIsScrollingNotifier.value) {
                timer ??= Timer(const Duration(milliseconds: 3000), () {
                  listIsScrollingNotifier.value = false;
                  timer = null;
                });
              }
            }
            return false;
          },
          child: pageContent(),
        ),
        Positioned(
          right: 30,
          bottom: 180,
          child: ValueListenableBuilder(
            valueListenable: listIsScrollingNotifier,
            builder: (context, value, child) {
              if (!value) {
                return SizedBox.shrink();
              }
              return IconButton(
                onPressed: () {
                  scrollController.animateTo(
                    0,
                    duration: Duration(milliseconds: 250),
                    curve: Curves.linear,
                  );
                },
                icon: ImageIcon(topArrowImage),
              );
            },
          ),
        ),

        Positioned(
          right: 30,
          bottom: 120,
          child: MyLocation(
            scrollController: scrollController,
            listIsScrollingNotifier: listIsScrollingNotifier,
            currentSongListNotifier: currentSongListNotifier,
            offset: 300 - MediaQuery.heightOf(context) / 2,
            displayIndexOf: (index) => albumStructureActive
                ? albumStructureDisplayIndex(index)
                : index,
          ),
        ),
      ],
    );
  }

  Widget pageHeader() {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;
    final shortSide = size.shortestSide;

    bool isPhone = shortSide < 600;

    return Column(
      children: [
        SizedBox(height: 10),
        Row(
          children: [
            SizedBox(width: 20),
            mainCover(isPhone ? 120 : 160),
            Expanded(
              child: ListTile(
                title: AutoSizeText(
                  getTitleText(l10n),
                  maxLines: 1,
                  minFontSize: 20,
                  maxFontSize: 20,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: ValueListenableBuilder(
                  valueListenable: currentSongListNotifier,
                  builder: (context, currentSongList, child) {
                    String prefix = getSourceTypeName(l10n, sourceType);
                    return Text(
                      "$prefix: ${l10n.songCount(currentSongList.length)}",
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
      ],
    );
  }

  // 专辑结构模式的专辑头行，样式对齐专辑页条目（封面 + 专辑名 + 歌数）
  Widget albumHeaderTile(List<MyAudioMetadata> currentSongList, int start) {
    final l10n = AppLocalizations.of(context);
    final song = currentSongList[start];
    final album = getAlbum(song);
    return ListTile(
      contentPadding: EdgeInsets.fromLTRB(20, 0, 20, 0),
      leading: CoverArtWidget(size: 40, borderRadius: 4, song: song),
      title: ValueListenableBuilder(
        valueListenable: currentSongNotifier,
        builder: (_, currentSong, _) {
          return ValueListenableBuilder(
            valueListenable: highlightTextColor.valueNotifier,
            builder: (context, value, child) {
              return Text(
                album,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  // 正在播放的专辑用高亮色区分，与歌曲行高亮一致
                  color: albumStructureGroupIsPlaying(album) ? value : null,
                ),
              );
            },
          );
        },
      ),
      subtitle: Text(
        l10n.songCount(albumStructureGroupCount(start)),
        style: TextStyle(fontSize: 12),
      ),
      trailing: Icon(
        collapsedAlbums.contains(album) ? Icons.expand_more : Icons.expand_less,
        color: iconColor.value,
      ),
      onTap: () {
        tryVibrate();
        toggleAlbumCollapsed(album);
      },
    );
  }

  Widget pageContent() {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverToBoxAdapter(child: pageHeader()),
        ValueListenableBuilder(
          valueListenable: currentSongListNotifier,
          builder: (context, currentSongList, child) {
            if (albumStructureActive) {
              return SliverFixedExtentList.builder(
                itemExtent: 60,
                itemCount: albumStructureRows.length,
                itemBuilder: (context, index) {
                  final row = albumStructureRows[index];
                  if (row < 0) {
                    return Center(
                      child: albumHeaderTile(currentSongList, -row - 1),
                    );
                  }
                  return Center(
                    child: SongListTile(
                      index: row,
                      songList: currentSongList,
                      folder: folder,
                      playlist: playlist,
                      isRanking: isRanking,
                      isLibrary: isLibrary,
                      reorderable: false,
                    ),
                  );
                },
              );
            }
            return SliverFixedExtentList.builder(
              itemExtent: 60,
              itemCount: currentSongList.length,
              itemBuilder: (context, index) {
                return Center(
                  child: SongListTile(
                    index: index,
                    songList: currentSongList,
                    folder: folder,
                    playlist: playlist,
                    isRanking: isRanking,
                    isLibrary: isLibrary,
                    reorderable:
                        reorderable &&
                        textController.text.isEmpty &&
                        sortTypeNotifier.value == 0,
                  ),
                );
              },
            );
          },
        ),
        SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }
}
