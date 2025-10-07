import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../drive_history_recorder.dart';

/// Renders a polished dashboard highlighting interesting events captured during
/// the current driving session.
class DriveInsightsPage extends StatefulWidget {
  const DriveInsightsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<DriveInsightsPage> createState() => _DriveInsightsPageState();
}

class _DriveInsightsPageState extends State<DriveInsightsPage> {
  late final DriveHistoryRecorder _recorder =
      widget.controller.driveHistoryRecorder;
  final ScrollController _scrollController = ScrollController();

  bool _canScrollUp = false;
  bool _canScrollDown = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScrollUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleScrollUpdate());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScrollUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScrollUpdate() {
    if (!_scrollController.hasClients) return;
    final ScrollPosition position = _scrollController.position;
    final bool canScrollUp = position.pixels > 72;
    final bool canScrollDown = position.maxScrollExtent - position.pixels > 72;
    if (canScrollUp != _canScrollUp || canScrollDown != _canScrollDown) {
      setState(() {
        _canScrollUp = canScrollUp;
        _canScrollDown = canScrollDown;
      });
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _scrollToBottom() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Color(0xFF0F2027),
            Color(0xFF203A43),
            Color(0xFF2C5364),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: ValueListenableBuilder<DriveSessionSummary>(
          valueListenable: _recorder.summary,
          builder: (BuildContext context, DriveSessionSummary summary, _) {
            return ValueListenableBuilder<List<DriveEvent>>(
              valueListenable: _recorder.events,
              builder: (BuildContext context, List<DriveEvent> events, __) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _handleScrollUpdate());
                return Stack(
                  children: <Widget>[
                    CustomScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      slivers: <Widget>[
                        SliverAppBar(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          pinned: true,
                          title: const Text(
                            'Drive insights',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                          centerTitle: false,
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            child: _SummaryHeader(
                              summary: summary,
                              eventCount: events.length,
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _SummaryGrid(summary: summary),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                          sliver: events.isEmpty
                              ? SliverToBoxAdapter(
                                  child: _EmptyState(theme: theme),
                                )
                              : SliverList.separated(
                                  itemCount: events.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 14),
                                  itemBuilder:
                                      (BuildContext context, int index) {
                                    return _TimelineTile(
                                        event:
                                            events[events.length - 1 - index],
                                        theme: theme);
                                  },
                                ),
                        ),
                      ],
                    ),
                    Positioned(
                      right: 20,
                      bottom: 24,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _ScrollFab(
                            icon: Icons.vertical_align_top,
                            label: 'Top',
                            visible: _canScrollUp,
                            onPressed: _scrollToTop,
                          ),
                          const SizedBox(height: 12),
                          _ScrollFab(
                            icon: Icons.vertical_align_bottom,
                            label: 'Bottom',
                            visible: _canScrollDown,
                            onPressed: _scrollToBottom,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.summary,
    required this.eventCount,
  });

  final DriveSessionSummary summary;
  final int eventCount;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Duration duration = summary.overspeedDuration;
    final String durationLabel = duration.inSeconds == 0
        ? 'No overspeed recorded'
        : 'Overspeed for ${_formatDuration(duration)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Professional drive log',
          style: textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          eventCount == 0
              ? 'Your next trip will appear here with beautiful metrics.'
              : 'Tracking $eventCount insight${eventCount == 1 ? '' : 's'} this session.',
          style: textTheme.bodyMedium?.copyWith(
            color: Colors.white70,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: <Widget>[
              _SummaryBadge(
                icon: Icons.speed,
                color: const Color(0xFF56CCF2),
                background: const Color(0x331C92F2),
                label: '${summary.speedCameraCount} cameras',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  durationLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (summary.maxOverspeed > 0)
                _SummaryBadge(
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFFFA726),
                  background: const Color(0x33FF9800),
                  label: 'Peak +${summary.maxOverspeed} km/h',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final DriveSessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final List<_MetricCardData> cards = <_MetricCardData>[
      _MetricCardData(
        icon: Icons.speed_sharp,
        label: 'Top speed',
        value: "${summary.topSpeed}km/h",
        gradient: const [
          Color.fromARGB(255, 215, 99, 136),
          Color.fromARGB(255, 189, 40, 155)
        ],
      ),
      _MetricCardData(
        icon: Icons.speed_outlined,
        label: 'Max acceleration',
        value: "${summary.maxAcceleration.toStringAsFixed(2)}m/s²",
        gradient: const [
          Color.fromARGB(117, 161, 227, 39),
          Color.fromARGB(226, 127, 201, 16)
        ],
      ),
      _MetricCardData(
        icon: Icons.my_location,
        label: 'Cameras passed',
        value: summary.speedCameraCount.toString(),
        gradient: const [Color(0xFF56CCF2), Color(0xFF2F80ED)],
      ),
      _MetricCardData(
        icon: Icons.engineering,
        label: 'Work zones',
        value: summary.constructionCount.toString(),
        gradient: const [Color(0xFFF7971E), Color(0xFFFF512F)],
      ),
      _MetricCardData(
        icon: Icons.shield_moon,
        label: 'Overspeed events',
        value: summary.overspeedCount.toString(),
        gradient: const [Color(0xFF00C9FF), Color(0xFF92FE9D)],
      ),
      _MetricCardData(
        icon: Icons.timer,
        label: 'Overspeed time',
        value: _formatDuration(summary.overspeedDuration),
        gradient: const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth;
        final bool isWide = maxWidth > 620;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards
              .map((card) => SizedBox(
                    width: isWide ? (maxWidth - 16) / 2 : maxWidth,
                    child: _MetricCard(data: card),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _MetricCardData {
  const _MetricCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
  });

  final IconData icon;
  final String label;
  final String value;
  final List<Color> gradient;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});

  final _MetricCardData data;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: data.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: data.gradient.last.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(10),
            child: Icon(data.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  data.value,
                  style: textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.label,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollFab extends StatelessWidget {
  const _ScrollFab({
    required this.icon,
    required this.label,
    required this.visible,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : const Offset(0, 0.6),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white24),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: onPressed,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.auto_awesome,
              color: Colors.white.withOpacity(0.6), size: 42),
          const SizedBox(height: 18),
          Text(
            'No events yet',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Start a drive to see cameras, construction alerts and overspeed '
            'analytics presented in real time.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  const _SummaryBadge({
    required this.icon,
    required this.color,
    required this.background,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.event, required this.theme});

  final DriveEvent event;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final Color accent = _accentColorForEvent(event.kind);
    final String timeLabel =
        TimeOfDay.fromDateTime(event.timestamp).format(context);
    final String subtitle = event.subtitle ??
        'Lat ${event.latitude.toStringAsFixed(4)}, '
            'Lon ${event.longitude.toStringAsFixed(4)}';
    final List<Widget> chips = <Widget>[];
    if (event.kind == DriveEventKind.overspeed && event.maxOverspeed != null) {
      chips.add(_EventChip(
        label: '+${event.maxOverspeed} km/h',
        color: accent,
      ));
    }
    final Duration? duration = event.duration;
    if (duration != null && duration.inSeconds > 0) {
      chips.add(_EventChip(
        label: _formatDuration(duration),
        color: Colors.white.withOpacity(0.14),
        textColor: Colors.white70,
      ));
    }
    if (event.details['flags'] is List &&
        (event.details['flags'] as List).isNotEmpty) {
      for (final dynamic flag in event.details['flags'] as List) {
        chips.add(_EventChip(
          label: flag.toString(),
          color: Colors.white.withOpacity(0.12),
          textColor: Colors.white70,
        ));
      }
    }
    if (event.isOngoing) {
      chips.add(_EventChip(
        label: 'LIVE',
        color: accent,
        textColor: Colors.black,
      ));
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: <Color>[
                      accent,
                      accent.withOpacity(0.65),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  _iconForEvent(event.kind),
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      event.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$subtitle · $timeLabel',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: chips,
            ),
          ],
        ],
      ),
    );
  }
}

class _EventChip extends StatelessWidget {
  const _EventChip({
    required this.label,
    required this.color,
    this.textColor,
  });

  final String label;
  final Color color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: textColor ?? Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
      ),
    );
  }
}

Color _accentColorForEvent(DriveEventKind kind) {
  switch (kind) {
    case DriveEventKind.speedCamera:
      return const Color(0xFF56CCF2);
    case DriveEventKind.construction:
      return const Color(0xFFFFA726);
    case DriveEventKind.overspeed:
      return const Color(0xFFEF5350);
    case DriveEventKind.topSpeed:
      return const Color(0xFFAB47BC);
    case DriveEventKind.maxAcceleration:
      return const Color.fromARGB(255, 130, 184, 23);
  }
}

IconData _iconForEvent(DriveEventKind kind) {
  switch (kind) {
    case DriveEventKind.speedCamera:
      return Icons.speed;
    case DriveEventKind.construction:
      return Icons.engineering;
    case DriveEventKind.overspeed:
      return Icons.warning_amber_rounded;
    case DriveEventKind.topSpeed:
      return Icons.speed_rounded;
    case DriveEventKind.maxAcceleration:
      return Icons.speed_outlined;
  }
}

String _formatDuration(Duration duration) {
  if (duration.inSeconds <= 0) return '0s';
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  final int seconds = duration.inSeconds.remainder(60);
  final List<String> parts = <String>[];
  if (hours > 0) parts.add('${hours}h');
  if (minutes > 0) parts.add('${minutes}m');
  if (seconds > 0 && hours == 0) parts.add('${seconds}s');
  return parts.join(' ');
}
