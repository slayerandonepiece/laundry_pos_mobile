import 'app_environment.dart';

class ApiEndpoints {
  ApiEndpoints._();

  /// Resolves the default base URL from active AppEnvironmentConfig
  static String get defaultBaseUrl => AppEnvironmentConfig.baseUrl;

  static String baseUrl = defaultBaseUrl;

  // Auth
  static String get login => '$baseUrl/api/v1/auth/login';
  static String get logout => '$baseUrl/api/v1/auth/logout';
  static String get syncStatus => '$baseUrl/api/v1/sync/status';
  static String get messageTemplates => '$baseUrl/api/v1/message-templates';
  static String get sessionStatus => '$baseUrl/api/v1/auth/status';
  static String get changePassword => '$baseUrl/api/v1/auth/change-password';
  static String get setPassword => '$baseUrl/api/v1/auth/set-password';

  // Account deletion (request, then restore during the grace period)
  static String get accountDeletion => '$baseUrl/api/v1/account/deletion';
  static String get accountDeletionRestore =>
      '$baseUrl/api/v1/account/deletion/restore';

  // Memberships
  static String get memberships => '$baseUrl/api/v1/memberships';

  // Products
  static String get products => '$baseUrl/api/v1/products';

  // Orders
  static String get orders => '$baseUrl/api/v1/orders';
  static String get ordersBulkSync => '$baseUrl/api/v1/orders/bulk-sync';
  static String get ordersSync => '$baseUrl/api/v1/orders/sync';
  static String customerLookup(String phone) =>
      '$baseUrl/api/v1/orders/customer-lookup?phone=${Uri.encodeQueryComponent(phone)}';
  static String orderDetail(String orderCode) =>
      '$baseUrl/api/v1/orders/$orderCode';
  static String orderStatus(String orderCode) =>
      '$baseUrl/api/v1/orders/$orderCode/status';
  static String orderPayments(String orderCode) =>
      '$baseUrl/api/v1/orders/$orderCode/payments';
  static String orderInvoice(String orderCode) =>
      '$baseUrl/api/v1/orders/$orderCode/invoice';
  static String orderCancel(String orderCode) =>
      '$baseUrl/api/v1/orders/$orderCode/cancel';
  static String orderMessage(String orderCode) =>
      '$baseUrl/api/v1/orders/$orderCode/message';
  static String orderInvoicePdf(String orderCode) =>
      '$baseUrl/api/v1/orders/$orderCode/invoice/pdf';

  // Subscription (owner billing history)
  static String get subscriptionInvoices =>
      '$baseUrl/api/v1/subscription/invoices';
  static String subscriptionInvoicePdf(int invoiceSeq) =>
      '$baseUrl/api/v1/subscription/invoices/$invoiceSeq/pdf';

  // Payment Methods
  static String get paymentMethods => '$baseUrl/api/v1/payment-methods';
  static String get paymentMethodsAll =>
      '$baseUrl/api/v1/payment-methods?all=true';
  static String paymentMethodDetail(String id) =>
      '$baseUrl/api/v1/payment-methods/$id';

  // Expenses
  static String get expenses => '$baseUrl/api/v1/expenses';
  static String expenseById(String id) => '$baseUrl/api/v1/expenses/$id';
  static String markExpensePaid(String id) =>
      '$baseUrl/api/v1/expenses/$id/pay';

  // Employees
  static String get employees => '$baseUrl/api/v1/employees';
  static String employeeDetail(String id) => '$baseUrl/api/v1/employees/$id';
  static String toggleEmployeeActive(String id) =>
      '$baseUrl/api/v1/employees/$id/toggle-active';

  // Profile
  static String get profile => '$baseUrl/api/v1/profile';

  // Dashboard
  static String get dashboard => '$baseUrl/api/v1/dashboard';
  static String get dashboardRollups => '$baseUrl/api/v1/dashboard/rollups';
}
