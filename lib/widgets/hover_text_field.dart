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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stackwallet/notifications/show_flush_bar.dart';
import 'package:stackwallet/providers/db/main_db_provider.dart';
import 'package:stackwallet/providers/global/wallets_provider.dart';
import 'package:stackwallet/themes/stack_colors.dart';
import 'package:stackwallet/utilities/constants.dart';
import 'package:stackwallet/utilities/text_styles.dart';
import 'package:stackwallet/utilities/util.dart';

class DesktopWalletNameField extends ConsumerStatefulWidget {
  const DesktopWalletNameField({
    Key? key,
    required this.walletId,
  }) : super(key: key);

  final String walletId;

  @override
  ConsumerState<DesktopWalletNameField> createState() => _HoverTextFieldState();
}

class _HoverTextFieldState extends ConsumerState<DesktopWalletNameField> {
  late final TextEditingController controller;
  late final FocusNode focusNode;
  bool readOnly = true;

  final InputBorder inputBorder = OutlineInputBorder(
    borderSide: const BorderSide(
      width: 0,
      color: Colors.transparent,
    ),
    borderRadius: BorderRadius.circular(Constants.size.circularBorderRadius),
  );

  Future<void> onDone() async {
    final info = ref.read(pWallets).getWallet(widget.walletId).info;
    final currentWalletName = info.name;
    final newName = controller.text;

    String? errMessage;
    try {
      await info.updateName(
        newName: newName,
        isar: ref.read(mainDBProvider).isar,
      );
    } catch (e) {
      if (e.toString().contains("Empty wallet name not allowed!")) {
        errMessage = "Empty wallet name not allowed.";
      } else {
        errMessage = e.toString();
      }
    }

    if (mounted) {
      if (errMessage == null) {
        unawaited(
          showFloatingFlushBar(
            type: FlushBarType.success,
            message: "Wallet renamed",
            context: context,
          ),
        );
      } else {
        unawaited(
          showFloatingFlushBar(
            type: FlushBarType.warning,
            message: "Wallet named \"$newName\" already exists",
            context: context,
          ),
        );
        controller.text = currentWalletName;
      }
    }
  }

  void listenerFunc() {
    if (!focusNode.hasPrimaryFocus && !readOnly) {
      setState(() {
        readOnly = true;
      });
      onDone.call();
    }
  }

  @override
  void initState() {
    controller = TextEditingController();
    focusNode = FocusNode();

    focusNode.addListener(listenerFunc);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.text = ref.read(pWallets).getWallet(widget.walletId).info.name;
    });

    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.removeListener(listenerFunc);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      autocorrect: !Util.isDesktop,
      enableSuggestions: !Util.isDesktop,
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly,
      onTap: () {
        setState(() {
          readOnly = false;
        });
      },
      onEditingComplete: () {
        setState(() {
          readOnly = true;
        });
        onDone.call();
      },
      style: STextStyles.desktopH3(context),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(
          vertical: 4,
          horizontal: 12,
        ),
        border: inputBorder,
        focusedBorder: inputBorder,
        disabledBorder: inputBorder,
        enabledBorder: inputBorder,
        errorBorder: inputBorder,
        fillColor: readOnly
            ? Colors.transparent
            : Theme.of(context).extension<StackColors>()!.textFieldDefaultBG,
      ),
    );
  }
}
