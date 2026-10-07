/// One platform subscription payment the owner can open as an invoice.
class SubscriptionInvoice {
  final int invoiceSeq;
  final String number;
  final String type; // 'DEPOSIT' | 'RENEWAL'
  final int amount; // paise
  final String? method;
  final String paidAt; // yyyy-MM-dd
  final String? coversFrom;
  final String? coversTo;

  const SubscriptionInvoice({
    required this.invoiceSeq,
    required this.number,
    required this.type,
    required this.amount,
    this.method,
    required this.paidAt,
    this.coversFrom,
    this.coversTo,
  });

  bool get isDeposit => type.toUpperCase() == 'DEPOSIT';

  String get title => isDeposit ? 'Subscription deposit' : 'Annual renewal';

  factory SubscriptionInvoice.fromJson(Map<String, dynamic> json) {
    return SubscriptionInvoice(
      invoiceSeq: (json['invoiceSeq'] as num?)?.toInt() ?? 0,
      number: json['number']?.toString() ?? '',
      type: json['type']?.toString() ?? 'RENEWAL',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      method: json['method']?.toString(),
      paidAt: json['paidAt']?.toString() ?? '',
      coversFrom: json['coversFrom']?.toString(),
      coversTo: json['coversTo']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'invoiceSeq': invoiceSeq,
    'number': number,
    'type': type,
    'amount': amount,
    'method': method,
    'paidAt': paidAt,
    'coversFrom': coversFrom,
    'coversTo': coversTo,
  };
}

/// The organization's billing terms, as the Billing page on the web shows
/// them. Amounts are paise. [planName] is null on custom terms.
class SubscriptionPlan {
  final String? planName;
  final int annualFeeAmount;
  final int depositAmount;

  const SubscriptionPlan({
    this.planName,
    required this.annualFeeAmount,
    required this.depositAmount,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) =>
      SubscriptionPlan(
        planName: json['planName']?.toString(),
        annualFeeAmount: (json['annualFeeAmount'] as num?)?.toInt() ?? 0,
        depositAmount: (json['depositAmount'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'planName': planName,
    'annualFeeAmount': annualFeeAmount,
    'depositAmount': depositAmount,
  };
}
