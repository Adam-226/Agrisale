// lib/main.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/product_screen.dart';
import 'screens/purchase_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/returns_screen.dart';
import 'screens/stock_report_screen.dart';
import 'screens/purchase_report_screen.dart';
import 'screens/sales_report_screen.dart';
import 'screens/returns_report_screen.dart';
import 'screens/total_sales_report_screen.dart';
import 'screens/financial_statistics_screen.dart';
import 'screens/customer_screen.dart';
import 'screens/supplier_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/data_assistant_screen.dart';

void main() {
  // 为桌面平台初始化SQLite
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // 初始化FFI
    sqfliteFfiInit();
    // 设置全局数据库工厂
    databaseFactory = databaseFactoryFfi;
  }
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agrisale',
      theme: ThemeData(
        primarySwatch: Colors.green, // 使用绿色作为主色调，与农资主题相符
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.green,
          accentColor: Colors.lightGreen, // 强调色
          brightness: Brightness.light,
        ),
        // 只在Windows平台设置字体，解决中文字体不一致问题，不影响其他平台
        textTheme: Platform.isWindows ? GoogleFonts.notoSansScTextTheme() : null,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.green,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        listTileTheme: ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        ),
        dataTableTheme: DataTableThemeData(
          headingRowColor: MaterialStateProperty.all(Colors.green[50]),
          dividerThickness: 1,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => LoginScreen(),
        '/main': (context) => MainScreen(),
        '/products': (context) => ProductScreen(),
        '/purchases': (context) => PurchaseScreen(),
        '/sales': (context) => SalesScreen(),
        '/returns': (context) => ReturnsScreen(),
        '/stock_report': (context) => StockReportScreen(),
        '/purchase_report': (context) => PurchaseReportScreen(),
        '/sales_report': (context) => SalesReportScreen(),
        '/returns_report': (context) => ReturnsReportScreen(),
        '/total_sales_report': (context) => TotalSalesReportScreen(),
        '/financial_statistics': (context) => FinancialStatisticsScreen(),
        '/customers': (context) => CustomerScreen(),
        '/suppliers': (context) => SupplierScreen(),
        '/settings': (context) => SettingsScreen(),
        '/data_assistant': (context) => DataAssistantScreen(),
      },
    );
  }
}