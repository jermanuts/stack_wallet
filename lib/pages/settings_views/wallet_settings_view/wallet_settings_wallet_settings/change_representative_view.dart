/*
 * This file is part of Stack Wallet.
 *
 * Copyright (c) 2023 Cypher Stack
 * All Rights Reserved.
 * The code is distributed under GPLv3 license, see LICENSE file for details.
 * Generated by Cypher Stack on 2023-05-26
 *
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:stackwallet/notifications/show_flush_bar.dart';
import 'package:stackwallet/providers/global/wallets_provider.dart';
import 'package:stackwallet/themes/stack_colors.dart';
import 'package:stackwallet/utilities/assets.dart';
import 'package:stackwallet/utilities/clipboard_interface.dart';
import 'package:stackwallet/utilities/constants.dart';
import 'package:stackwallet/utilities/show_loading.dart';
import 'package:stackwallet/utilities/text_styles.dart';
import 'package:stackwallet/utilities/util.dart';
import 'package:stackwallet/wallets/wallet/wallet_mixin_interfaces/nano_interface.dart';
import 'package:stackwallet/widgets/background.dart';
import 'package:stackwallet/widgets/conditional_parent.dart';
import 'package:stackwallet/widgets/custom_buttons/app_bar_icon_button.dart';
import 'package:stackwallet/widgets/desktop/desktop_dialog.dart';
import 'package:stackwallet/widgets/desktop/desktop_dialog_close_button.dart';
import 'package:stackwallet/widgets/desktop/primary_button.dart';
import 'package:stackwallet/widgets/icon_widgets/x_icon.dart';
import 'package:stackwallet/widgets/loading_indicator.dart';
import 'package:stackwallet/widgets/rounded_white_container.dart';
import 'package:stackwallet/widgets/stack_text_field.dart';
import 'package:stackwallet/widgets/textfield_icon_button.dart';

class ChangeRepresentativeView extends ConsumerStatefulWidget {
  const ChangeRepresentativeView({
    Key? key,
    required this.walletId,
    this.clipboardInterface = const ClipboardWrapper(),
  }) : super(key: key);

  final String walletId;
  final ClipboardInterface clipboardInterface;

  static const String routeName = "/changeRepresentative";

  @override
  ConsumerState<ChangeRepresentativeView> createState() =>
      _ChangeRepresentativeViewState();
}

class _ChangeRepresentativeViewState
    extends ConsumerState<ChangeRepresentativeView> {
  final _textController = TextEditingController();
  final _textFocusNode = FocusNode();
  final bool isDesktop = Util.isDesktop;

  late ClipboardInterface _clipboardInterface;

  String? representative;

  Future<String> loadRepresentative() async {
    final wallet = ref.read(pWallets).getWallet(widget.walletId);

    if (wallet is NanoInterface) {
      return wallet.getCurrentRepresentative();
    } else {
      throw Exception("Unsupported wallet attempted to show representative!");
    }
  }

  Future<void> _save() async {
    final wallet =
        ref.read(pWallets).getWallet(widget.walletId) as NanoInterface;

    final changeFuture = wallet.changeRepresentative;

    final result = await showLoading(
        whileFuture: changeFuture(_textController.text),
        context: context,
        message: "Updating representative...",
        isDesktop: Util.isDesktop,
        onException: (ex) {
          String msg = ex.toString();
          while (msg.isNotEmpty && msg.startsWith("Exception:")) {
            msg = msg.substring(10).trim();
          }
          showFloatingFlushBar(
            type: FlushBarType.warning,
            message: msg,
            context: context,
          );
        });

    if (mounted) {
      if (result != null && result) {
        setState(() {
          representative = _textController.text;
          _textController.text = "";
        });
        await showFloatingFlushBar(
          type: FlushBarType.success,
          message: "Representative changed",
          context: context,
        );
      }
    }
  }

  @override
  void initState() {
    _clipboardInterface = widget.clipboardInterface;

    super.initState();
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await _clipboardInterface
        .setData(ClipboardData(text: representative ?? ""));
    if (mounted) {
      unawaited(showFloatingFlushBar(
        type: FlushBarType.info,
        message: "Copied to clipboard",
        iconAsset: Assets.svg.copy,
        context: context,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConditionalParent(
      condition: !isDesktop,
      builder: (child) => Background(
        child: SafeArea(
          child: Scaffold(
            backgroundColor:
                Theme.of(context).extension<StackColors>()!.background,
            appBar: AppBar(
              leading: AppBarBackButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                },
              ),
              title: Text(
                "Wallet representative",
                style: STextStyles.navBarTitle(context),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: AppBarIconButton(
                      color: Theme.of(context)
                          .extension<StackColors>()!
                          .background,
                      shadows: const [],
                      icon: SvgPicture.asset(
                        Assets.svg.copy,
                        width: 24,
                        height: 24,
                        color: Theme.of(context)
                            .extension<StackColors>()!
                            .topNavIconPrimary,
                      ),
                      onPressed: () {
                        if (representative != null) {
                          _copy();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            body: Padding(
              padding: const EdgeInsets.only(
                top: 12,
                left: 16,
                right: 16,
              ),
              child: child,
            ),
          ),
        ),
      ),
      child: ConditionalParent(
        condition: isDesktop,
        builder: (child) => DesktopDialog(
          maxWidth: 600,
          maxHeight: double.infinity,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 32,
                    ),
                    child: Text(
                      "Change representative",
                      style: STextStyles.desktopH2(context),
                    ),
                  ),
                  DesktopDialogCloseButton(
                    onPressedOverride: Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop,
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(
                  milliseconds: 150,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                  child: child,
                ),
              ),
            ],
          ),
        ),
        child: Column(
          children: [
            if (isDesktop) const SizedBox(height: 24),
            ConditionalParent(
              condition: !isDesktop,
              builder: (child) => Expanded(
                child: child,
              ),
              child: FutureBuilder(
                future: loadRepresentative(),
                builder: (context, AsyncSnapshot<String> snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData) {
                    representative = snapshot.data!;
                  }

                  const height = 600.0;
                  Widget child;
                  if (representative == null) {
                    child = const SizedBox(
                      key: Key("loadingRepresentative"),
                      height: height,
                      child: Center(
                        child: LoadingIndicator(
                          width: 100,
                        ),
                      ),
                    );
                  } else {
                    child = Column(
                      children: [
                        ConditionalParent(
                          condition: !isDesktop,
                          builder: (child) => RoundedWhiteContainer(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                child,
                              ],
                            ),
                          ),
                          child: ConditionalParent(
                            condition: isDesktop,
                            builder: (child) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Current representative",
                                  style: STextStyles.desktopTextExtraExtraSmall(
                                      context),
                                ),
                                const SizedBox(
                                  height: 4,
                                ),
                                Row(
                                  children: [
                                    child,
                                  ],
                                ),
                              ],
                            ),
                            child: SelectableText(
                              representative!,
                              style: isDesktop
                                  ? STextStyles.desktopTextExtraExtraSmall(
                                          context)
                                      .copyWith(
                                      color: Theme.of(context)
                                          .extension<StackColors>()!
                                          .textDark,
                                    )
                                  : STextStyles.itemSubtitle12(context),
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 24,
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            Constants.size.circularBorderRadius,
                          ),
                          child: TextField(
                            autocorrect: Util.isDesktop ? false : true,
                            enableSuggestions: Util.isDesktop ? false : true,
                            controller: _textController,
                            style: isDesktop
                                ? STextStyles.desktopTextExtraSmall(context)
                                    .copyWith(
                                    color: Theme.of(context)
                                        .extension<StackColors>()!
                                        .textFieldActiveText,
                                    height: 1.8,
                                  )
                                : STextStyles.field(context),
                            focusNode: _textFocusNode,
                            decoration: standardInputDecoration(
                              "Enter new representative",
                              _textFocusNode,
                              context,
                              desktopMed: isDesktop,
                            ).copyWith(
                              contentPadding: isDesktop
                                  ? const EdgeInsets.only(
                                      left: 16,
                                      top: 11,
                                      bottom: 12,
                                      right: 5,
                                    )
                                  : null,
                              suffixIcon: _textController.text.isNotEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.only(right: 0),
                                      child: UnconstrainedBox(
                                        child: Row(
                                          children: [
                                            TextFieldIconButton(
                                              child: const XIcon(),
                                              onTap: () async {
                                                setState(() {
                                                  _textController.text = "";
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        if (isDesktop) const SizedBox(height: 60),
                        if (!isDesktop) const Spacer(),
                        PrimaryButton(
                          label: "Save",
                          onPressed: _save,
                        ),
                        if (!isDesktop)
                          const SizedBox(
                            height: 16,
                          ),
                      ],
                    );
                  }

                  return AnimatedSwitcher(
                    duration: const Duration(
                      milliseconds: 200,
                    ),
                    child: child,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}