import 'package:flutter/material.dart';
import 'package:stackwallet/utilities/cfcolors.dart';
import 'package:stackwallet/utilities/text_styles.dart';
import 'package:stackwallet/widgets/stack_dialog.dart';

class ConfirmRecoveryDialog extends StatelessWidget {
  const ConfirmRecoveryDialog({Key? key, required this.onConfirm})
      : super(key: key);

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        return true;
      },
      child: StackDialog(
        title: "Are you ready?",
        message:
            "Restoring your wallet may take a while. Please do not exit this screen once the process is started.",
        leftButton: TextButton(
          style: Theme.of(context).textButtonTheme.style?.copyWith(
                backgroundColor: MaterialStateProperty.all<Color>(
                  CFColors.buttonGray,
                ),
              ),
          child: Text(
            "Cancel",
            style: STextStyles.itemSubtitle12,
          ),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        rightButton: TextButton(
          style: Theme.of(context).textButtonTheme.style?.copyWith(
                backgroundColor: MaterialStateProperty.all<Color>(
                  CFColors.stackAccent,
                ),
              ),
          child: Text(
            "Restore",
            style: STextStyles.button,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm.call();
          },
        ),
      ),
    );
  }
}