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

/// Sub-layout choice for the 3-pane portrait mode (Task 44).
///
/// `topRowAndSplitBottom` is the original layout from Task 17 step 6:
/// the first pane fills the full width on top and the remaining two panes
/// share a horizontally-split bottom row.
///
/// `equalColumns` is the additional layout introduced by Task 44: three
/// equal-width vertical columns side-by-side. On a Galaxy S10+ class phone
/// (720 logical-px portrait width) this yields ~240 px per pane.
enum ThreePanePortraitLayout { topRowAndSplitBottom, equalColumns }

/// Sub-layout choice for the 3-pane landscape mode (Task 45).
///
/// `leftLargeRightStacked` is the original layout from Task 17 step 6:
/// a large left pane and two vertically-stacked right panes.
///
/// `equalRows` is the additional layout introduced by Task 45: three
/// equal-height horizontal rows stacked top-to-bottom.
enum ThreePaneLandscapeLayout { leftLargeRightStacked, equalRows }
