/* 
 * This file is part of Stack Wallet.
 * 
 * Copyright (c) 2023 Cypher Stack
 * All Rights Reserved.
 * The code is distributed under GPLv3 license, see LICENSE file for details.
 * Generated by Cypher Stack on 2023-05-26
 *
 */

import 'package:decimal/decimal.dart';
import 'package:stackwallet/models/exchange/majestic_bank/mb_object.dart';

class MBLimit extends MBObject {
  MBLimit({
    required this.currency,
    required this.min,
    required this.max,
  });

  final String currency;
  final Decimal min;
  final Decimal max;

  @override
  String toString() {
    return "MBLimit: { $currency: { min: $min, max: $max } }";
  }
}
