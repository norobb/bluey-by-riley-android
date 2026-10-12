import 'package:flutter/material.dart';
import '../protocol/googly_protocol.dart';

class SoundButton extends StatefulWidget {
  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onSayHi;
  final bool isConnected;
  final List<String> macs;
  final String? currentMac;
  final ValueChanged<String>? onChooseMac;

  const SoundButton({
    super.key,
    required this.volume,
    required this.onVolumeChanged,
    required this.onSayHi,
    required this.isConnected,
    required this.macs,
    this.currentMac,
    this.onChooseMac,
  });

  @override
  State<SoundButton> createState() => _SoundButtonState();
}

class _SoundButtonState extends State<SoundButton> {
  bool _open = false;

  IconData get _speakerIcon {
    if (widget.volume < 0.01) return Icons.volume_off;
    if (widget.volume < 0.5) return Icons.volume_down;
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, right: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(_open ? Icons.close : _speakerIcon),
              color: Colors.white.withOpacity(_open ? 0.9 : 0.35),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(_open ? 0.14 : 0.06),
              ),
            ),
            if (_open) ...[
              const SizedBox(height: 10),
              Container(
                width: 260,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(Palette.panel).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "CHIRP VOLUME",
                          style: TextStyle(
                            fontFamily: 'IBMPlexMono',
                            fontSize: 12,
                            color: Color(Palette.inkSoft),
                          ),
                        ),
                        Text(
                          "${(widget.volume * 100).round()}%",
                          style: const TextStyle(
                            fontFamily: 'IBMPlexMono',
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: widget.volume,
                      onChanged: widget.onVolumeChanged,
                      activeColor: const Color(Palette.berry2),
                      inactiveColor: Colors.white.withOpacity(0.2),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: widget.isConnected ? widget.onSayHi : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(Palette.berry2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Say hi",
                          style: TextStyle(
                            fontFamily: 'IBMPlexSans',
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (widget.macs.length > 1) ...[
                      const SizedBox(height: 12),
                      const Text(
                        "MAC",
                        style: TextStyle(
                          fontFamily: 'IBMPlexMono',
                          fontSize: 12,
                          color: Color(Palette.inkSoft),
                        ),
                      ),
                      ...widget.macs.map((name) {
                        final isSelected = name == widget.currentMac;
                        return InkWell(
                          onTap: () => widget.onChooseMac?.call(name),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontFamily: 'IBMPlexSans',
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    widget.isConnected ? Icons.check : Icons.more_horiz,
                                    color: const Color(Palette.berry2),
                                    size: 18,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                    if (!widget.isConnected) ...[
                      const SizedBox(height: 8),
                      const Text(
                        "Connect to your computer to talk to him.",
                        style: TextStyle(
                          fontFamily: 'IBMPlexSans',
                          fontSize: 12,
                          color: Color(Palette.inkSoft),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
