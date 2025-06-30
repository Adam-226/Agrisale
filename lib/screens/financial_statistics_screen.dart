// lib/screens/financial_statistics_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:table_calendar/table_calendar.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';

class FinancialStatisticsScreen extends StatefulWidget {
  @override
  _FinancialStatisticsScreenState createState() => _FinancialStatisticsScreenState();
}

class _FinancialStatisticsScreenState extends State<FinancialStatisticsScreen> {
  List<Map<String, dynamic>> _dailyStatistics = [];
  List<Map<String, dynamic>> _monthlyStatistics = [];
  List<Map<String, dynamic>> _products = [];
  String? _selectedProduct = '所有产品'; // 默认选择"所有产品"
  bool _isDescending = true; // 默认按时间倒序排列
  int _currentIndex = 0; // 当前选中的Tab索引
  Set<String> _datesWithRecords = {}; // 存储有记录的日期
  Set<String> _monthsWithRecords = {}; // 存储有记录的月份
  ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
    _fetchProducts();
    _fetchStatistics();
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDescending = prefs.getBool('financial_sort_descending') ?? true;
    });
  }

  Future<void> _saveSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('financial_sort_descending', _isDescending);
  }

  Future<void> _fetchProducts() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        // 只获取当前用户的产品
        final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _products = products;
        });
      }
    }
  }

  Future<void> _fetchStatistics() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final orderBy = _isDescending ? 'DESC' : 'ASC';
        String productFilter = _selectedProduct != null && _selectedProduct != '所有产品'
            ? "AND productName = '$_selectedProduct'"
            : '';

        // 清空记录日期和月份集合
        _datesWithRecords.clear();
        _monthsWithRecords.clear();

        // 获取当前用户的每日统计
        final dailySales = await db.rawQuery('''
          SELECT saleDate, SUM(totalSalePrice) as totalSales
          FROM sales
          WHERE userId = ? $productFilter
          GROUP BY saleDate
          ORDER BY saleDate $orderBy
        ''', [userId]);

    // 添加销售记录的日期
    for (var sale in dailySales) {
      _datesWithRecords.add(sale['saleDate'] as String);
      _monthsWithRecords.add((sale['saleDate'] as String).substring(0, 7));
    }

        final dailyReturns = await db.rawQuery('''
          SELECT returnDate, SUM(totalReturnPrice) as totalReturns
          FROM returns
          WHERE userId = ? $productFilter
          GROUP BY returnDate
          ORDER BY returnDate $orderBy
        ''', [userId]);

    // 添加退货记录的日期
    for (var returnItem in dailyReturns) {
      _datesWithRecords.add(returnItem['returnDate'] as String);
      _monthsWithRecords.add((returnItem['returnDate'] as String).substring(0, 7));
    }

        final dailyPurchases = await db.rawQuery('''
          SELECT purchaseDate, SUM(totalPurchasePrice) as totalPurchases
          FROM purchases
          WHERE userId = ? $productFilter
          GROUP BY purchaseDate
          ORDER BY purchaseDate $orderBy
        ''', [userId]);

    // 添加采购记录的日期
    for (var purchase in dailyPurchases) {
      _datesWithRecords.add(purchase['purchaseDate'] as String);
      _monthsWithRecords.add((purchase['purchaseDate'] as String).substring(0, 7));
    }

    // 合并每日销售、退货和采购数据
    final dailyMap = <String, Map<String, double>>{};
    for (var sale in dailySales) {
      final date = sale['saleDate'] as String;
      final totalSales = sale['totalSales'] as double? ?? 0.0;
      dailyMap[date] = {'totalSales': totalSales, 'totalPurchases': 0.0};
    }
    for (var returnItem in dailyReturns) {
      final date = returnItem['returnDate'] as String;
      final totalReturns = returnItem['totalReturns'] as double? ?? 0.0;
      dailyMap[date] = dailyMap[date] ?? {'totalSales': 0.0, 'totalPurchases': 0.0};
      dailyMap[date]!['totalSales'] = (dailyMap[date]!['totalSales'] ?? 0) - totalReturns;
    }
    for (var purchase in dailyPurchases) {
      final date = purchase['purchaseDate'] as String;
      final totalPurchases = purchase['totalPurchases'] as double? ?? 0.0;
      dailyMap[date] = dailyMap[date] ?? {'totalSales': 0.0, 'totalPurchases': 0.0};
      dailyMap[date]!['totalPurchases'] = totalPurchases;
    }

    // 创建统计列表并手动排序
    final dailyEntries = dailyMap.entries.map((entry) {
      return {
        'date': entry.key,
        'totalSales': entry.value['totalSales'],
        'totalPurchases': entry.value['totalPurchases']
      };
    }).toList();
    
    // 根据日期手动排序
    dailyEntries.sort((a, b) {
      int compareResult = (a['date'] as String).compareTo(b['date'] as String);
      return _isDescending ? -compareResult : compareResult;
    });
    
    _dailyStatistics = dailyEntries;

        // 获取当前用户的每月统计
        final monthlySales = await db.rawQuery('''
          SELECT strftime('%Y-%m', saleDate) as month, SUM(totalSalePrice) as totalSales
          FROM sales
          WHERE userId = ? $productFilter
          GROUP BY month
          ORDER BY month $orderBy
        ''', [userId]);

        final monthlyReturns = await db.rawQuery('''
          SELECT strftime('%Y-%m', returnDate) as month, SUM(totalReturnPrice) as totalReturns
          FROM returns
          WHERE userId = ? $productFilter
          GROUP BY month
          ORDER BY month $orderBy
        ''', [userId]);

        final monthlyPurchases = await db.rawQuery('''
          SELECT strftime('%Y-%m', purchaseDate) as month, SUM(totalPurchasePrice) as totalPurchases
          FROM purchases
          WHERE userId = ? $productFilter
          GROUP BY month
          ORDER BY month $orderBy
        ''', [userId]);

    // 合并每月销售、退货和采购数据
    final monthlyMap = <String, Map<String, double>>{};
    for (var sale in monthlySales) {
      final month = sale['month'] as String;
      final totalSales = sale['totalSales'] as double? ?? 0.0;
      monthlyMap[month] = {'totalSales': totalSales, 'totalPurchases': 0.0};
    }
    for (var returnItem in monthlyReturns) {
      final month = returnItem['month'] as String;
      final totalReturns = returnItem['totalReturns'] as double? ?? 0.0;
      monthlyMap[month] = monthlyMap[month] ?? {'totalSales': 0.0, 'totalPurchases': 0.0};
      monthlyMap[month]!['totalSales'] = (monthlyMap[month]!['totalSales'] ?? 0) - totalReturns;
    }
    for (var purchase in monthlyPurchases) {
      final month = purchase['month'] as String;
      final totalPurchases = purchase['totalPurchases'] as double? ?? 0.0;
      monthlyMap[month] = monthlyMap[month] ?? {'totalSales': 0.0, 'totalPurchases': 0.0};
      monthlyMap[month]!['totalPurchases'] = totalPurchases;
    }

    // 创建统计列表并手动排序
    final monthlyEntries = monthlyMap.entries.map((entry) {
      return {
        'month': entry.key,
        'totalSales': entry.value['totalSales'],
        'totalPurchases': entry.value['totalPurchases']
      };
    }).toList();
    
    // 根据月份手动排序
    monthlyEntries.sort((a, b) {
      int compareResult = (a['month'] as String).compareTo(b['month'] as String);
      return _isDescending ? -compareResult : compareResult;
    });
    
        _monthlyStatistics = monthlyEntries;

        setState(() {});
      }
    }
  }

  void _toggleSortOrder() {
    setState(() {
      _isDescending = !_isDescending;
      _saveSortPreference();
      _fetchStatistics();
    });
  }

  Future<void> _exportToCSV() async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    List<List<dynamic>> rows = [];
    // 添加用户信息和导出时间
    rows.add(['财务统计报告 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    rows.add(['产品筛选: ${_selectedProduct ?? '所有产品'}']);
    rows.add([]); // 空行
    // 修改表头为中文
    rows.add(['日期/月份', '总销售额', '总进货价', '利润']);

    List<Map<String, dynamic>> statistics = _currentIndex == 0 ? _dailyStatistics : _monthlyStatistics;
    String dateKey = _currentIndex == 0 ? 'date' : 'month';

    for (var stat in statistics) {
      final totalSales = stat['totalSales'] as double;
      final totalPurchases = stat['totalPurchases'] as double;
      final profit = totalSales - totalPurchases;
      
      List<dynamic> row = [];
      row.add(stat[dateKey]);
      row.add(totalSales);
      row.add(totalPurchases);
      row.add(profit);
      rows.add(row);
    }

    String csv = const ListToCsvConverter().convert(rows);

    if (Platform.isMacOS || Platform.isWindows) {
      // macOS 和 Windows: 使用 file_picker 让用户选择保存位置
      String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存财务统计报告',
        fileName: 'financial_statistics.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      
      if (selectedPath != null) {
        final file = File(selectedPath);
        await file.writeAsString(csv);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出成功: $selectedPath')),
        );
      }
      return;
    }

    String path;
    if (Platform.isAndroid) {
      // 请求存储权限
      if (await Permission.storage.request().isGranted) {
        final directory = Directory('/storage/emulated/0/Download');
        path = '${directory.path}/financial_statistics.csv';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('存储权限被拒绝')),
        );
        return;
      }
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/financial_statistics.csv';
    } else {
      // 其他平台使用应用文档目录作为后备方案
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/financial_statistics.csv';
    }

    final file = File(path);
    await file.writeAsString(csv);

    if (Platform.isIOS) {
      // iOS 让用户手动选择存储位置
      await Share.shareFiles([file.path], text: '财务统计 CSV 文件');
    } else {
      // Android 直接存入 Download 目录，并提示用户
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出成功: $path')),
      );
    }
  }

  // 显示日历对话框
  void _showCalendarDialog() {
    DateTime focusedDay = DateTime.now();
    DateTime? selectedDay;
    CalendarFormat calendarFormat = _currentIndex == 0 ? CalendarFormat.month : CalendarFormat.month;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(_currentIndex == 0 ? '选择日期' : '选择月份'),
            content: Container(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_currentIndex == 0)
                  // 每日统计使用常规日历
                  TableCalendar(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: focusedDay,
                    selectedDayPredicate: (day) {
                      return selectedDay != null && isSameDay(selectedDay!, day);
                    },
                    onDaySelected: (selected, focused) {
                      setState(() {
                        selectedDay = selected;
                        focusedDay = focused;
                      });
                    },
                    calendarFormat: calendarFormat,
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                    ),
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                      markerDecoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, focusedDay) {
                        // 将日期格式化为 "yyyy-MM-dd" 格式
                        String formattedDate = "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
                        
                        // 检查是否有记录
                        bool hasRecord = _datesWithRecords.contains(formattedDate);
                        
                        return Container(
                          margin: const EdgeInsets.all(4.0),
                          alignment: Alignment.center,
                          decoration: hasRecord 
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.green, width: 1.5),
                                  shape: BoxShape.circle,
                                ) 
                              : null,
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              color: hasRecord ? Colors.green : null,
                              fontWeight: hasRecord ? FontWeight.bold : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_currentIndex == 1)
                  // 每月统计使用月份选择器
                  Container(
                    height: 300,
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.5,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: 36, // 显示3年的月份
                      itemBuilder: (context, index) {
                        // 从当前年份往前推1年，往后推1年
                        final now = DateTime.now();
                        final year = now.year - 1 + (index ~/ 12);
                        final month = (index % 12) + 1; // 1-12月
                        
                        final formattedMonth = "$year-${month.toString().padLeft(2, '0')}";
                        final hasRecord = _monthsWithRecords.contains(formattedMonth);
                        
                        // 检查是否是被选中的月份
                        final isSelected = selectedDay != null && 
                            selectedDay!.year == year && 
                            selectedDay!.month == month;
                            
                        return InkWell(
                          onTap: () {
                            setState(() {
                              selectedDay = DateTime(year, month, 1);
                              focusedDay = selectedDay!;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? Colors.amber
                                  : hasRecord 
                                      ? Colors.amber.withOpacity(0.1)
                                      : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: hasRecord
                                  ? Border.all(color: Colors.green, width: 1.5)
                                  : Border.all(color: Colors.grey[300]!, width: 1),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$year年',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? Colors.white : Colors.grey[700],
                                  ),
                                ),
                                Text(
                                  '$month月',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected 
                                        ? Colors.white 
                                        : hasRecord 
                                            ? Colors.green
                                            : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    _currentIndex == 0 
                        ? '绿色边框表示有交易记录'
                        : '绿色边框表示该月有交易记录',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  if (selectedDay != null) {
                    Navigator.of(context).pop();
                    _jumpToDate(selectedDay!);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('请先选择一个${_currentIndex == 0 ? '日期' : '月份'}')),
                    );
                  }
                },
                child: Text('跳转'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 跳转到指定日期的记录
  void _jumpToDate(DateTime selectedDate) {
    String formattedDate = "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";
    String formattedMonth = "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}";

    // 根据当前标签页选择日期或月份
    String targetDate = _currentIndex == 0 ? formattedDate : formattedMonth;
    List<Map<String, dynamic>> statistics = _currentIndex == 0 ? _dailyStatistics : _monthlyStatistics;
    String dateKey = _currentIndex == 0 ? 'date' : 'month';

    // 查找目标日期的索引
    int targetIndex = -1;
    for (int i = 0; i < statistics.length; i++) {
      if (statistics[i][dateKey] == targetDate) {
        targetIndex = i;
        break;
      }
    }

    // 如果找到记录，滚动到该位置
    if (targetIndex != -1) {
      // 延迟执行，确保界面已经构建完成
      Future.delayed(Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          targetIndex * 160.0, // 估计每个卡片高度约为160
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已跳转到 $targetDate 的记录')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('未找到 $targetDate 的记录')),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('财务统计', style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )),
          bottom: TabBar(
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            indicatorColor: Colors.amber,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal),
            tabs: [
              Tab(
                icon: Icon(Icons.calendar_today, size: 18),
                text: '每日统计',
              ),
              Tab(
                icon: Icon(Icons.date_range, size: 18),
                text: '每月统计',
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(_isDescending ? Icons.arrow_downward : Icons.arrow_upward),
              tooltip: _isDescending ? '最新在前' : '最早在前',
              onPressed: _toggleSortOrder,
            ),
            IconButton(
              icon: Icon(Icons.download),
              tooltip: '导出 CSV',
              onPressed: _exportToCSV,
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.amber[50],
              child: Row(
                children: [
                  Icon(Icons.filter_alt, color: Colors.amber[700], size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber[300]!),
                          color: Colors.white,
                        ),
                        child: DropdownButton<String>(
                          hint: Text('选择产品', style: TextStyle(color: Colors.black87)),
                          value: _selectedProduct,
                          isExpanded: true,
                          icon: Icon(Icons.arrow_drop_down, color: Colors.amber[700]),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedProduct = newValue;
                              _fetchStatistics();
                            });
                          },
                          style: TextStyle(color: Colors.black87, fontSize: 15),
                          items: [
                            DropdownMenuItem<String>(
                              value: '所有产品',
                              child: Text('所有产品'),
                            ),
                            ..._products.map<DropdownMenuItem<String>>((product) {
                              return DropdownMenuItem<String>(
                                value: product['name'],
                                child: Text(product['name']),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  // 添加日历按钮
                  Material(
                    color: Colors.amber[100],
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: _showCalendarDialog,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.amber[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.calendar_month,
                          color: Colors.amber[800],
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(
                    _currentIndex == 0 
                        ? Icons.calendar_today 
                        : Icons.date_range,
                    color: Colors.amber[800],
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    _currentIndex == 0 ? '每日财务统计' : '每月财务统计',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber[800],
                    ),
                  ),
                  Spacer(),
                  Text(
                    '排序: ${_isDescending ? '最新在前' : '最早在前'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    _isDescending ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 14,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
            Expanded(
              child: TabBarView(
                children: [
                  _buildStatisticsView(_dailyStatistics, 'date', '日期'),
                  _buildStatisticsView(_monthlyStatistics, 'month', '月份'),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: FooterWidget(),
      ),
    );
  }

  Widget _buildStatisticsView(List<Map<String, dynamic>> statistics, String dateKey, String dateLabel) {
    if (statistics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentIndex == 0 ? Icons.calendar_today : Icons.date_range,
              size: 64,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              '暂无${_currentIndex == 0 ? '每日' : '每月'}统计数据',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 8),
            Text(
              _selectedProduct == '所有产品'
                  ? '添加销售或采购记录后会显示在这里'
                  : '当前筛选: $_selectedProduct，可能没有相关记录',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      controller: _scrollController,
      itemCount: statistics.length,
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemBuilder: (context, index) {
        final stat = statistics[index];
        final totalSales = stat['totalSales'] as double;
        final totalPurchases = stat['totalPurchases'] as double;
        final profit = totalSales - totalPurchases;
        
        return Card(
          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber[200]!),
                          ),
                          child: Icon(
                            _currentIndex == 0
                                ? Icons.calendar_today
                                : Icons.date_range,
                            size: 16,
                            color: Colors.amber[700],
                          ),
                        ),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stat[dateKey] as String,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${_currentIndex == 0 ? '日' : '月'}度统计',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: profit >= 0 ? Colors.green[50] : Colors.red[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: profit >= 0 ? Colors.green[300]! : Colors.red[300]!,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '利润: ¥ ${profit.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: profit >= 0 ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.shopping_bag,
                                    size: 12,
                                    color: Colors.blue[700],
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '总销售额',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8, top: 6),
                              child: Text(
                                '¥ ${totalSales.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        color: Colors.grey[300],
                        margin: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.inventory,
                                    size: 12,
                                    color: Colors.green[700],
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '总进货价',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8, top: 6),
                              child: Text(
                                '¥ ${totalPurchases.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.green[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: totalSales > 0 ? (profit / totalSales).clamp(0.0, 1.0) : 0,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      profit >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  profit >= 0
                      ? '利润率: ${totalSales > 0 ? ((profit / totalSales) * 100).toStringAsFixed(1) : 0}%'
                      : '亏损率: ${totalSales > 0 ? ((-profit / totalSales) * 100).toStringAsFixed(1) : 0}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: profit >= 0 ? Colors.green[700] : Colors.red[700],
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}