import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/owner/data/models/store_profile_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/change_password_screen.dart';
import 'package:myshop/features/owner/presentation/owner_profile_screen.dart';
import 'package:myshop/features/owner/presentation/payment_methods_screen.dart';
import 'package:myshop/features/owner/presentation/store_profile_screen.dart';

class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc([AuthState? state]) : super(state ?? UnauthenticatedState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProfileOwnerRepository extends OwnerRepository {
  StoreProfile storeProfile;
  List<StorePaymentMethod> paymentMethods = [];

  Map<String, String>? lastUpdatedStoreProfile;
  Map<String, dynamic>? lastToggledPaymentMethod;

  FakeProfileOwnerRepository({required this.storeProfile})
    : super(apiClient: ApiClient());

  @override
  Future<StoreProfile> getStoreProfile() async {
    return storeProfile;
  }

  @override
  Future<StoreProfile> updateStoreProfile({
    required String storeName,
    required String address,
    required String phone,
    required String name,
    required String email,
  }) async {
    lastUpdatedStoreProfile = {
      'storeName': storeName,
      'address': address,
      'phone': phone,
      'name': name,
      'email': email,
    };
    storeProfile = StoreProfile(
      store: storeName,
      address: address,
      phone: phone,
      name: name,
      email: email,
    );
    return storeProfile;
  }

  @override
  Future<List<StorePaymentMethod>> listPaymentMethods() async {
    return paymentMethods;
  }

  @override
  Future<void> togglePaymentMethod(String id, bool active) async {
    lastToggledPaymentMethod = {'id': id, 'active': active};
    final index = paymentMethods.indexWhere((m) => m.id == id);
    if (index >= 0) {
      paymentMethods[index] = StorePaymentMethod(
        id: id,
        code: paymentMethods[index].code,
        name: paymentMethods[index].name,
        type: paymentMethods[index].type,
        active: active,
      );
    }
  }
}

void main() {
  group('Owner Profile Screens Web Parity & Bugfix Tests', () {
    late FakeProfileOwnerRepository fakeRepo;
    late OwnerBloc ownerBloc;
    late MockAuthBloc authBloc;

    setUp(() {
      fakeRepo = FakeProfileOwnerRepository(
        storeProfile: StoreProfile(
          store: 'Express Laundry Demo',
          address: '123 Main Street, Bangalore',
          phone: '9876543210',
          name: 'John Doe',
          email: 'john@example.com',
        ),
      );
      fakeRepo.paymentMethods = [
        StorePaymentMethod(
          id: 'pm-1',
          name: 'Cash',
          type: 'Cash',
          active: true,
        ),
        StorePaymentMethod(
          id: 'pm-2',
          name: 'UPI QR',
          type: 'UPI',
          active: true,
        ),
      ];

      ownerBloc = OwnerBloc(ownerRepository: fakeRepo);

      final user = User(id: 'usr-1', name: 'John Doe', username: 'johndoe');
      final store = StoreSummary(
        storeId: 'store-1',
        storeName: 'Express Laundry Demo',
        role: 'OWNER',
      );
      authBloc = MockAuthBloc(
        AuthenticatedState(
          user: user,
          currentStore: store,
          availableStores: [store],
        ),
      );
    });

    Widget wrapScreen(Widget child) {
      return MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<OwnerBloc>.value(value: ownerBloc),
            BlocProvider<AuthBloc>.value(value: authBloc),
          ],
          child: child,
        ),
      );
    }

    Future<void> pumpAsync(WidgetTester tester) async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    testWidgets(
      '1. Saving from OwnerProfileScreen sends all 5 fields including carried-over store/address',
      (tester) async {
        await tester.pumpWidget(wrapScreen(const OwnerProfileScreen()));
        await pumpAsync(tester);

        expect(find.text('Your details'), findsOneWidget);
        expect(find.text('@johndoe'), findsOneWidget);
        expect(find.text('Store Owner'), findsOneWidget);

        final textFields = find.byType(TextField);
        expect(textFields, findsNWidgets(3));

        // Initial pre-filled values
        expect(find.text('John Doe'), findsOneWidget);
        expect(find.text('9876543210'), findsOneWidget);
        expect(find.text('john@example.com'), findsOneWidget);

        // Edit fields
        await tester.enterText(textFields.at(0), 'John Smith');
        await tester.enterText(textFields.at(1), '9123456780');
        await tester.enterText(textFields.at(2), 'johnsmith@example.com');
        await tester.pumpAndSettle();

        // Tap Save changes
        await tester.tap(find.text('Save changes'));
        await pumpAsync(tester);

        expect(fakeRepo.lastUpdatedStoreProfile, isNotNull);
        expect(fakeRepo.lastUpdatedStoreProfile!['name'], 'John Smith');
        expect(fakeRepo.lastUpdatedStoreProfile!['phone'], '9123456780');
        expect(
          fakeRepo.lastUpdatedStoreProfile!['email'],
          'johnsmith@example.com',
        );
        // Carried over store and address
        expect(
          fakeRepo.lastUpdatedStoreProfile!['storeName'],
          'Express Laundry Demo',
        );
        expect(
          fakeRepo.lastUpdatedStoreProfile!['address'],
          '123 Main Street, Bangalore',
        );
      },
    );

    testWidgets(
      '2. Saving from StoreProfileScreen sends all 5 fields including carried-over name/email (regression test)',
      (tester) async {
        await tester.pumpWidget(wrapScreen(const StoreProfileScreen()));
        await pumpAsync(tester);

        expect(find.text('Store profile'), findsOneWidget);
        expect(
          find.text('Currency: INR · Timezone: Asia/Kolkata'),
          findsOneWidget,
        );

        final textFields = find.byType(TextField);
        expect(textFields, findsNWidgets(3));

        // Edit store fields
        await tester.enterText(textFields.at(0), 'Updated Laundry Store');
        await tester.enterText(textFields.at(1), '456 New Road, Indiranagar');
        await tester.enterText(textFields.at(2), '08044445555');
        await tester.pumpAndSettle();

        // Save profile
        await tester.tap(find.text('Save profile'));
        await pumpAsync(tester);

        expect(fakeRepo.lastUpdatedStoreProfile, isNotNull);
        expect(
          fakeRepo.lastUpdatedStoreProfile!['storeName'],
          'Updated Laundry Store',
        );
        expect(
          fakeRepo.lastUpdatedStoreProfile!['address'],
          '456 New Road, Indiranagar',
        );
        expect(fakeRepo.lastUpdatedStoreProfile!['phone'], '08044445555');
        // Critical data-loss fix: name and email must NOT be empty
        expect(fakeRepo.lastUpdatedStoreProfile!['name'], 'John Doe');
        expect(fakeRepo.lastUpdatedStoreProfile!['email'], 'john@example.com');
      },
    );

    testWidgets(
      '3. PaymentMethodsScreen toggle dispatches TogglePaymentMethodEvent and renders no Add/Rename UI',
      (tester) async {
        await tester.pumpWidget(wrapScreen(const PaymentMethodsScreen()));
        await pumpAsync(tester);

        expect(find.text('Cash'), findsWidgets);
        expect(find.text('UPI QR'), findsOneWidget);
        expect(
          find.text(
            'Payment methods are managed by the platform. Enable the ones you accept.',
          ),
          findsOneWidget,
        );

        // No Add or Rename UI rendered
        expect(find.text('Rename'), findsNothing);
        expect(find.text('Add payment method'), findsNothing);
        expect(find.text('Add method'), findsNothing);
        expect(find.byType(TextField), findsNothing);

        // Toggle the first Switch (Cash: active true -> false)
        final switches = find.byType(Switch);
        expect(switches, findsNWidgets(2));
        await tester.tap(switches.first);
        await pumpAsync(tester);

        expect(fakeRepo.lastToggledPaymentMethod, isNotNull);
        expect(fakeRepo.lastToggledPaymentMethod!['id'], 'pm-1');
        expect(fakeRepo.lastToggledPaymentMethod!['active'], isFalse);

        fakeRepo.paymentMethods = [
          StorePaymentMethod(
            id: 'pm-3',
            code: 'COD',
            name: 'Pay on delivery',
          ),
        ];
        await tester.tap(find.byIcon(Icons.refresh_rounded));
        await pumpAsync(tester);

        expect(find.text('COD'), findsOneWidget);
        expect(find.text('Cash'), findsNothing);
      },
    );

    test(
      '4. StorePaymentMethod.fromJson parses code and toJson round-trips',
      () {
        final method = StorePaymentMethod.fromJson({
          'id': 'pm1',
          'code': 'CARD',
          'name': 'Card',
          'enabled': true,
        });
        expect(method.code, 'CARD');
        final roundTripped = StorePaymentMethod.fromJson(method.toJson());
        expect(roundTripped.id, 'pm1');
        expect(roundTripped.code, 'CARD');
        expect(roundTripped.name, 'Card');
        expect(roundTripped.active, isTrue);
      },
    );

    testWidgets(
      '5. "Show passwords" checkbox in ChangePasswordScreen toggles obscureText on all 3 fields',
      (tester) async {
        await tester.pumpWidget(wrapScreen(const ChangePasswordScreen()));
        await tester.pumpAndSettle();

        // 3 password text fields
        List<TextField> getTextFields() {
          return tester.widgetList<TextField>(find.byType(TextField)).toList();
        }

        var fields = getTextFields();
        expect(fields.length, 3);
        expect(fields[0].obscureText, isTrue);
        expect(fields[1].obscureText, isTrue);
        expect(fields[2].obscureText, isTrue);

        // Checkbox exists
        expect(find.text('Show passwords'), findsOneWidget);
        final checkbox = find.byType(Checkbox);
        expect(checkbox, findsOneWidget);

        // Tap Show passwords
        await tester.tap(checkbox);
        await tester.pumpAndSettle();

        fields = getTextFields();
        expect(fields[0].obscureText, isFalse);
        expect(fields[1].obscureText, isFalse);
        expect(fields[2].obscureText, isFalse);

        // Tap again to hide passwords
        await tester.tap(checkbox);
        await tester.pumpAndSettle();

        fields = getTextFields();
        expect(fields[0].obscureText, isTrue);
        expect(fields[1].obscureText, isTrue);
        expect(fields[2].obscureText, isTrue);
      },
    );
  });
}
