/*
 * Copyright (c) 2024-2026 Fabian Freund.
 *
 * This file is part of WebLibre
 * (see https://weblibre.eu).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
import 'package:fading_scroll/fading_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:weblibre/features/settings/presentation/controllers/save_settings.dart';
import 'package:weblibre/features/settings/presentation/widgets/sections.dart';
import 'package:weblibre/features/user/data/models/general_settings.dart';
import 'package:weblibre/features/user/domain/repositories/general_settings.dart';

class HomepageSettingsScreen extends StatelessWidget {
  const HomepageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Homepage')),
      body: SafeArea(
        child: FadingScroll(
          fadingSize: 25,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              children: const [_ShortcutsSection(), _OpeningScreenSection()],
            );
          },
        ),
      ),
    );
  }
}

// ── Shortcuts ─────────────────────────────────────────────────────────────────

class _ShortcutsSection extends StatelessWidget {
  const _ShortcutsSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SettingSection(name: 'Shortcuts'),
        _JumpBackInTile(),
        _BookmarksTile(),
        _RecentlyVisitedTile(),
      ],
    );
  }
}

class _JumpBackInTile extends HookConsumerWidget {
  const _JumpBackInTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      generalSettingsWithDefaultsProvider.select(
        (s) => s.homepageShowJumpBackIn,
      ),
    );

    return SwitchListTile.adaptive(
      title: const Text('Jump back in'),
      subtitle: const Text('Show recently visited tabs on the home screen'),
      secondary: const Icon(MdiIcons.history),
      value: enabled,
      onChanged: (value) async {
        await ref
            .read(saveGeneralSettingsControllerProvider.notifier)
            .save((s) => s.copyWith.homepageShowJumpBackIn(value));
      },
    );
  }
}

class _BookmarksTile extends HookConsumerWidget {
  const _BookmarksTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      generalSettingsWithDefaultsProvider.select(
        (s) => s.homepageShowBookmarks,
      ),
    );

    return SwitchListTile.adaptive(
      title: const Text('Bookmarks'),
      subtitle: const Text('Show bookmarks shortcuts on the home screen'),
      secondary: const Icon(Icons.bookmark_outline),
      value: enabled,
      onChanged: (value) async {
        await ref
            .read(saveGeneralSettingsControllerProvider.notifier)
            .save((s) => s.copyWith.homepageShowBookmarks(value));
      },
    );
  }
}

class _RecentlyVisitedTile extends HookConsumerWidget {
  const _RecentlyVisitedTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      generalSettingsWithDefaultsProvider.select(
        (s) => s.homepageShowRecentlyVisited,
      ),
    );

    return SwitchListTile.adaptive(
      title: const Text('Recently visited'),
      subtitle: const Text('Show recently visited sites on the home screen'),
      secondary: const Icon(MdiIcons.clockOutline),
      value: enabled,
      onChanged: (value) async {
        await ref
            .read(saveGeneralSettingsControllerProvider.notifier)
            .save((s) => s.copyWith.homepageShowRecentlyVisited(value));
      },
    );
  }
}

// ── Opening screen ─────────────────────────────────────────────────────────────

class _OpeningScreenSection extends HookConsumerWidget {
  const _OpeningScreenSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openingScreen = ref.watch(
      generalSettingsWithDefaultsProvider.select(
        (s) => s.homepageOpeningScreen,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingSection(name: 'Opening screen'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
          child: RadioGroup(
            groupValue: openingScreen,
            onChanged: (value) async {
              if (value != null) {
                await ref
                    .read(saveGeneralSettingsControllerProvider.notifier)
                    .save((s) => s.copyWith.homepageOpeningScreen(value));
              }
            },
            child: const Column(
              children: [
                RadioListTile.adaptive(
                  value: HomepageOpeningScreen.homepage,
                  title: Text('Homepage'),
                  subtitle: Text('Always open the home screen on startup'),
                ),
                RadioListTile.adaptive(
                  value: HomepageOpeningScreen.lastTab,
                  title: Text('Last tab'),
                  subtitle: Text('Resume where you left off'),
                ),
                RadioListTile.adaptive(
                  value: HomepageOpeningScreen.homepageAfterFourHours,
                  title: Text('Homepage after four hours of inactivity'),
                  subtitle: Text(
                    'Resume last tab unless the app has been idle for 4+ hours',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
