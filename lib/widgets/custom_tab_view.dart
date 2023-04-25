import 'package:flutter/material.dart';
import 'package:stackwallet/utilities/text_styles.dart';
import 'package:stackwallet/utilities/theme/stack_colors.dart';

class CustomTabView extends StatefulWidget {
  const CustomTabView({
    Key? key,
    required this.titles,
    required this.children,
    this.initialIndex = 0,
    this.childPadding,
  })  : assert(titles.length == children.length),
        super(key: key);

  final List<String> titles;
  final List<Widget> children;
  final int initialIndex;
  final EdgeInsets? childPadding;

  @override
  State<CustomTabView> createState() => _CustomTabViewState();
}

class _CustomTabViewState extends State<CustomTabView> {
  late int _selectedIndex;

  static const duration = Duration(milliseconds: 250);

  @override
  void initState() {
    _selectedIndex = widget.initialIndex;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (int i = 0; i < widget.titles.length; i++)
                Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedIndex = i),
                      child: Container(
                        color: Colors.transparent,
                        child: Column(
                          children: [
                            const SizedBox(
                              height: 16,
                            ),
                            AnimatedCrossFade(
                              firstChild: Text(
                                widget.titles[i],
                                style:
                                    STextStyles.desktopTextExtraSmall(context)
                                        .copyWith(
                                  color: Theme.of(context)
                                      .extension<StackColors>()!
                                      .accentColorBlue,
                                ),
                              ),
                              secondChild: Text(
                                widget.titles[i],
                                style:
                                    STextStyles.desktopTextExtraSmall(context)
                                        .copyWith(
                                  color: Theme.of(context)
                                      .extension<StackColors>()!
                                      .textSubtitle1,
                                ),
                              ),
                              crossFadeState: _selectedIndex == i
                                  ? CrossFadeState.showFirst
                                  : CrossFadeState.showSecond,
                              duration: const Duration(milliseconds: 250),
                            ),
                            const SizedBox(
                              height: 19,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Stack(
            children: [
              Container(
                height: 2,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .extension<StackColors>()!
                      .backgroundAppBar,
                ),
              ),
              AnimatedSlide(
                offset: Offset(_selectedIndex.toDouble(), 0),
                duration: duration,
                child: Container(
                  height: 2,
                  width: constraints.maxWidth / widget.titles.length,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .extension<StackColors>()!
                        .accentColorBlue,
                  ),
                ),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: duration,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            layoutBuilder: (currentChild, prevChildren) {
              return Stack(
                alignment: Alignment.topCenter,
                children: [
                  ...prevChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            child: AnimatedAlign(
              key: Key("${widget.titles[_selectedIndex]}_customTabKey"),
              alignment: Alignment.topCenter,
              duration: duration,
              child: Padding(
                padding: widget.childPadding ?? EdgeInsets.zero,
                child: widget.children[_selectedIndex],
              ),
            ),
          ),
        ],
      ),
    );
  }
}