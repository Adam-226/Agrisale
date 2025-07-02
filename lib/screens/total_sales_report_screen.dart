import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';

class TotalSalesReportScreen extends StatefulWidget {
  @override
  _TotalSalesReportScreenState createState() => _TotalSalesReportScreenState();
}

class _TotalSalesReportScreenState extends State<TotalSalesReportScreen> {
  List<Map<String, dynamic>> _allCombinedRecords = []; // 存储所有合并记录
  List<Map<String, dynamic>> _combinedRecords = []; // 存储筛选后的合并记录
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _products = [];
  bool _isDescending = true; // 默认按时间倒序排列
  
  // 筛选条件
  String? _selectedProductName;
  int? _selectedCustomerId;
  DateTime? _startDate;
  DateTime? _endDate;
  
  // 统计数据
  double _totalQuantity = 0.0;
  double _totalPrice = 0.0;

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
    _fetchData();
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDescending = prefs.getBool('total_sales_sort_descending') ?? true;
    });
  }

  Future<void> _saveSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('total_sales_sort_descending', _isDescending);
  }

  Future<void> _fetchData() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final orderBy = _isDescending ? 'DESC' : 'ASC';
        
        // 获取当前用户的销售数据
        final sales = await db.rawQuery('''
          SELECT 
            saleDate AS date, 
            productName, 
            quantity, 
            customerId, 
            totalSalePrice AS totalPrice,
            note,
            'sale' AS type
          FROM sales
          WHERE userId = ?
          ORDER BY date $orderBy
        ''', [userId]);

        // 获取当前用户的退货数据
        final returns = await db.rawQuery('''
          SELECT 
            returnDate AS date, 
            productName, 
            quantity, 
            customerId, 
            totalReturnPrice AS totalPrice,
            note,
            'return' AS type
          FROM returns
          WHERE userId = ?
          ORDER BY date $orderBy
        ''', [userId]);

        // 只获取当前用户的客户和产品数据
        final customers = await db.query('customers', where: 'userId = ?', whereArgs: [userId]);
        final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);

    // 合并销售和退货数据
    List<Map<String, dynamic>> combinedRecords = [];
    
    // 添加销售数据（正值）
    for (var sale in sales) {
      combinedRecords.add({
        'date': sale['date'],
        'productName': sale['productName'],
        'quantity': sale['quantity'],
        'customerId': sale['customerId'],
        'totalPrice': sale['totalPrice'],
        'note': sale['note'],
        'type': '销售',
        'value': 1 // 正值标记
      });
    }
    
    // 添加退货数据（负值）
    for (var returnItem in returns) {
      combinedRecords.add({
        'date': returnItem['date'],
        'productName': returnItem['productName'],
        'quantity': returnItem['quantity'],
        'customerId': returnItem['customerId'],
        'totalPrice': returnItem['totalPrice'],
        'note': returnItem['note'],
        'type': '退货',
        'value': -1 // 负值标记
      });
    }

    // 按日期排序
    combinedRecords.sort((a, b) {
      if (_isDescending) {
        return b['date'].toString().compareTo(a['date'].toString());
      } else {
        return a['date'].toString().compareTo(b['date'].toString());
      }
    });

        setState(() {
          _allCombinedRecords = combinedRecords;
          _customers = customers;
          _products = products;
          _applyFilters(); // 应用筛选
        });
      }
    }
  }
  
  // 应用筛选条件
  void _applyFilters() {
    List<Map<String, dynamic>> filteredRecords = List.from(_allCombinedRecords);
    
    // 按产品名称筛选
    if (_selectedProductName != null) {
      filteredRecords = filteredRecords.where(
        (record) => record['productName'] == _selectedProductName
      ).toList();
    }
    
    // 按客户筛选
    if (_selectedCustomerId != null) {
      filteredRecords = filteredRecords.where(
        (record) => record['customerId'] == _selectedCustomerId
      ).toList();
    }
    
    // 按日期范围筛选
    if (_startDate != null) {
      filteredRecords = filteredRecords.where((record) {
        final recordDate = DateTime.parse(record['date']);
        return recordDate.isAfter(_startDate!) || 
               recordDate.isAtSameMomentAs(_startDate!);
      }).toList();
    }
    
    if (_endDate != null) {
      final endDatePlusOne = _endDate!.add(Duration(days: 1)); // 包含结束日期
      filteredRecords = filteredRecords.where((record) {
        final recordDate = DateTime.parse(record['date']);
        return recordDate.isBefore(endDatePlusOne);
      }).toList();
    }
    
    // 计算总量和总金额
    _calculateTotals(filteredRecords);
    
    setState(() {
      _combinedRecords = filteredRecords;
    });
  }
  
  // 计算总量和总金额
  void _calculateTotals(List<Map<String, dynamic>> filteredRecords) {
    double totalQuantity = 0.0;
    double totalPrice = 0.0;
    
    for (var record in filteredRecords) {
      // 销售是正值，退货是负值
      if (record['type'] == '销售') {
        totalQuantity += (record['quantity'] as num).toDouble();
        totalPrice += (record['totalPrice'] as num).toDouble();
      } else {
        totalQuantity -= (record['quantity'] as num).toDouble();
        totalPrice -= (record['totalPrice'] as num).toDouble();
      }
    }
    
    setState(() {
      _totalQuantity = totalQuantity;
      _totalPrice = totalPrice;
    });
  }
  
  // 重置筛选条件
  void _resetFilters() {
    setState(() {
      _selectedProductName = null;
      _selectedCustomerId = null;
      _startDate = null;
      _endDate = null;
      _combinedRecords = _allCombinedRecords;
      _calculateTotals(_combinedRecords);
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _isDescending = !_isDescending;
      _saveSortPreference();
      _fetchData();
    });
  }

  void _navigateToTableView() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TotalSalesTableScreen(
          records: _combinedRecords,
          customers: _customers,
          products: _products,
          totalQuantity: _totalQuantity,
          totalPrice: _totalPrice,
        ),
      ),
    );
  }
  
  // 显示筛选菜单
  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '筛选与刷新',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    icon: Icon(Icons.refresh),
                    label: Text('刷新数据'),
                    onPressed: () {
                      _fetchData();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.inventory, color: Colors.green),
                title: Text('按产品筛选'),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showProductSelectionDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.person, color: Colors.orange),
                title: Text('按客户筛选'),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showCustomerSelectionDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.date_range, color: Colors.purple),
                title: Text('按日期范围筛选'),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showDateRangePickerDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.sort, color: Colors.purple),
                title: Text('切换排序顺序'),
                subtitle: Text(_isDescending ? '当前: 最新在前' : '当前: 最早在前'),
                onTap: () {
                  _toggleSortOrder();
                  Navigator.pop(context);
                },
              ),
              if (_hasFilters())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.clear_all),
                    label: Text('清除所有筛选条件'),
                    onPressed: () {
                      _resetFilters();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[400],
                      minimumSize: Size(double.infinity, 44),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
  
  // 检查是否有筛选条件
  bool _hasFilters() {
    return _selectedProductName != null || 
           _selectedCustomerId != null || 
           _startDate != null || 
           _endDate != null;
  }
  
  // 选择产品对话框
  Future<void> _showProductSelectionDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('选择产品'),
          content: Container(
            width: double.maxFinite,
            child: _products.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无产品数据', textAlign: TextAlign.center),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _products.length,
                    itemBuilder: (context, index) {
                      final product = _products[index];
                      return ListTile(
                        title: Text(product['name']),
                        onTap: () {
                          setState(() {
                            _selectedProductName = product['name'];
                            _applyFilters();
                          });
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
  
  // 选择客户对话框
  Future<void> _showCustomerSelectionDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('选择客户'),
          content: Container(
            width: double.maxFinite,
            child: _customers.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无客户数据', textAlign: TextAlign.center),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _customers.length,
                    itemBuilder: (context, index) {
                      final customer = _customers[index];
                      return ListTile(
                        title: Text(customer['name']),
                        onTap: () {
                          setState(() {
                            _selectedCustomerId = customer['id'];
                            _applyFilters();
                          });
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
  
  // 选择日期范围对话框
  Future<void> _showDateRangePickerDialog() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null 
          ? DateTimeRange(start: _startDate!, end: _endDate!) 
          : null,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.purple,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _applyFilters();
      });
    }
  }
  
     // 格式化数字显示：整数显示为整数，小数显示为小数
   String _formatNumber(dynamic number) {
     if (number == null) return '0';
     double value = number is double ? number : double.tryParse(number.toString()) ?? 0.0;
     if (value == value.floor()) {
       return value.toInt().toString();
     } else {
       return value.toString();
    }
  }
  
  // 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('总销售报告', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          IconButton(
            icon: Icon(Icons.table_chart),
            tooltip: '表格视图',
            onPressed: _navigateToTableView,
          ),
          IconButton(
            icon: Icon(Icons.more_vert),
            tooltip: '更多选项',
            onPressed: _showFilterOptions,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 筛选条件指示器
          _buildFilterIndicator(),
          
          // 统计信息
          if (_combinedRecords.isNotEmpty && _hasFilters())
            _buildSummaryCard(),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.assessment, color: Colors.purple[700], size: 20),
                SizedBox(width: 8),
                Text(
                  '销售与退货综合记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple[800],
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
          _combinedRecords.isEmpty 
            ? Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assessment, size: 64, color: Colors.grey[400]),
                      SizedBox(height: 16),
                      Text(
                        _allCombinedRecords.isEmpty ? '暂无交易记录' : '没有符合条件的记录',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _allCombinedRecords.isEmpty ? '添加销售或退货记录后会显示在这里' : '请尝试更改筛选条件',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                      if (!_allCombinedRecords.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.clear),
                            label: Text('清除筛选条件'),
                            onPressed: _resetFilters,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            : Expanded(
                child: RefreshIndicator(
                  onRefresh: _fetchData,
                  child: ListView.builder(
                    itemCount: _combinedRecords.length,
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    itemBuilder: (context, index) {
                      final record = _combinedRecords[index];
                      final customer = _customers.firstWhere(
                        (c) => c['id'] == record['customerId'],
                        orElse: () => {'name': '未知客户'},
                      );
                      final product = _products.firstWhere(
                        (p) => p['name'] == record['productName'],
                        orElse: () => {'unit': ''},
                      );
                      
                      // 设置颜色，销售为绿色，退货为红色
                      Color textColor = record['type'] == '销售' ? Colors.green : Colors.red;
                      
                      // 根据类型决定金额正负
                      String amount = record['type'] == '销售' 
                          ? '${record['totalPrice']}' 
                          : '-${record['totalPrice']}';
                      
                      return Card(
                        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        record['date'],
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: record['type'] == '销售' 
                                              ? Colors.green[50] 
                                              : Colors.red[50],
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: record['type'] == '销售' 
                                                ? Colors.green[300]! 
                                                : Colors.red[300]!,
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          record['type'],
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '¥ $amount',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: textColor,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                record['productName'],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.inventory_2, 
                                       size: 14, 
                                       color: Colors.blue[700]),
                                  SizedBox(width: 4),
                                  Text(
                                    '数量: ${_formatNumber(record['quantity'])} ${product['unit']}',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  SizedBox(width: 16),
                                  Icon(Icons.person, 
                                       size: 14, 
                                       color: Colors.orange[700]),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '客户: ${customer['name']}',
                                      style: TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (record['note'] != null && record['note'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      Icon(Icons.note, 
                                           size: 14, 
                                           color: Colors.grey[600]),
                                      SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          '备注: ${record['note']}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700],
                                            fontStyle: FontStyle.italic,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          FooterWidget(),
        ],
      ),
    );
  }
  
  // 筛选条件指示器
  Widget _buildFilterIndicator() {
    if (!_hasFilters()) {
      return SizedBox.shrink(); // 没有筛选条件，不显示指示器
    }
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.purple[50],
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_selectedProductName != null)
                  Chip(
                    label: Text('产品: $_selectedProductName'),
                    deleteIcon: Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedProductName = null;
                        _applyFilters();
                      });
                    },
                    backgroundColor: Colors.green[100],
                  ),
                if (_selectedCustomerId != null)
                  Chip(
                    label: Text('客户: ${_customers.firstWhere(
                      (c) => c['id'] == _selectedCustomerId,
                      orElse: () => {'name': '未知'}
                    )['name']}'),
                    deleteIcon: Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedCustomerId = null;
                        _applyFilters();
                      });
                    },
                    backgroundColor: Colors.orange[100],
                  ),
                if (_startDate != null || _endDate != null)
                  Chip(
                    label: Text(
                      '时间: ${_startDate != null ? _formatDate(_startDate!) : '无限制'} 至 ${_endDate != null ? _formatDate(_endDate!) : '无限制'}'
                    ),
                    deleteIcon: Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _startDate = null;
                        _endDate = null;
                        _applyFilters();
                      });
                    },
                    backgroundColor: Colors.purple[100],
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 20),
            tooltip: '清除所有筛选',
            onPressed: _resetFilters,
          ),
        ],
      ),
    );
  }
  
  // 统计摘要卡片
  Widget _buildSummaryCard() {
    final String productUnit = _selectedProductName != null 
        ? (_products.firstWhere(
            (p) => p['name'] == _selectedProductName,
            orElse: () => {'unit': ''}
          )['unit'] ?? '')
        : '';

    final String priceSign = _totalPrice >= 0 ? '+' : '';
    final Color priceColor = _totalPrice >= 0 ? Colors.green : Colors.red;
    final String quantitySign = _totalQuantity >= 0 ? '+' : '';
    final Color quantityColor = _totalQuantity >= 0 ? Colors.green : Colors.red;
    
    return Card(
      margin: EdgeInsets.all(8),
      color: Colors.purple[50],
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '统计信息',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.purple[800],
              ),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('总记录数: ${_combinedRecords.length}'),
                Text(
                  '净数量: $quantitySign${_formatNumber(_totalQuantity)} ${_selectedProductName != null ? productUnit : ""}',
                  style: TextStyle(color: quantityColor),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '净收入: $priceSign¥${_totalPrice.toStringAsFixed(2)}',
                  style: TextStyle(color: priceColor, fontWeight: FontWeight.bold),
                ),
                if (_selectedProductName != null && _totalQuantity != 0 && _totalPrice != 0)
                  Text('平均单价: ¥${(_totalPrice / _totalQuantity).abs().toStringAsFixed(2)}/${productUnit}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TotalSalesTableScreen extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> products;
  final double totalQuantity;
  final double totalPrice;

  TotalSalesTableScreen({
    required this.records,
    required this.customers,
    required this.products,
    required this.totalQuantity,
    required this.totalPrice,
  });

  // 格式化数字显示：整数显示为整数，小数显示为小数
  String _formatNumber(dynamic number) {
    if (number == null) return '0';
    double value = number is double ? number : double.tryParse(number.toString()) ?? 0.0;
    if (value == value.floor()) {
      return value.toInt().toString();
    } else {
      return value.toString();
    }
  }

  Future<void> _exportToCSV(BuildContext context) async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    String csvData = '总销售报告 - 用户: $username\n';
    csvData += '导出时间: ${DateTime.now().toString().substring(0, 19)}\n\n';
    csvData += '日期,类型,产品,数量,单位,客户,总金额,备注\n';
    for (var record in records) {
      final customer = customers.firstWhere(
        (c) => c['id'] == record['customerId'],
        orElse: () => {'name': '未知客户'},
      );
      final product = products.firstWhere(
        (p) => p['name'] == record['productName'],
        orElse: () => {'unit': ''},
      );
      
      // 根据类型决定金额正负
      String amount = record['type'] == '销售' 
          ? record['totalPrice'].toString() 
          : '-${record['totalPrice']}';
      
      // 根据类型决定数量正负
      String quantity = record['type'] == '销售'
          ? _formatNumber(record['quantity'])
          : '-${_formatNumber(record['quantity'])}';
      
      csvData += '${record['date']},${record['type']},${record['productName']},$quantity,${product['unit']},${customer['name']},$amount,${record['note'] ?? ''}\n';
    }
    
    // 添加统计信息
    csvData += '\n总计,,,,,\n';
    csvData += '记录数,${records.length}\n';
    csvData += '净数量,${_formatNumber(totalQuantity)}\n';
    csvData += '净收入,${totalPrice.toStringAsFixed(2)}\n';

    if (Platform.isMacOS || Platform.isWindows) {
      // macOS 和 Windows: 使用 file_picker 让用户选择保存位置
      String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存总销售报告',
        fileName: 'total_sales_report.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      
      if (selectedPath != null) {
        final file = File(selectedPath);
        await file.writeAsString(csvData);
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
        path = '${directory.path}/total_sales_report.csv';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('存储权限被拒绝')),
        );
        return;
      }
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/total_sales_report.csv';
    } else {
      // 其他平台使用应用文档目录作为后备方案
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/total_sales_report.csv';
    }

    final file = File(path);
    await file.writeAsString(csvData);

    if (Platform.isIOS) {
      // iOS 让用户手动选择存储位置
      await Share.shareFiles([file.path], text: '总销售报告 CSV 文件');
    } else {
      // Android 直接存入 Download 目录，并提示用户
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出成功: $path')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 处理正负符号和颜色
    final String quantitySign = totalQuantity >= 0 ? '+' : '';
    final Color quantityColor = totalQuantity >= 0 ? Colors.green : Colors.red;
    final String priceSign = totalPrice >= 0 ? '+' : '';
    final Color priceColor = totalPrice >= 0 ? Colors.green : Colors.red;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('总销售报告表格', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          IconButton(
            icon: Icon(Icons.download),
            tooltip: '导出 CSV',
            onPressed: () => _exportToCSV(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            color: Colors.purple[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.purple[700], size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '横向和纵向滑动可查看更多数据，点击右上角图标可导出CSV文件',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.purple[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 添加统计摘要
          if (records.isNotEmpty)
            Container(
              padding: EdgeInsets.all(12),
              color: Colors.purple[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text('记录数', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('${records.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      Text('净数量', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('$quantitySign${_formatNumber(totalQuantity)}', 
                           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: quantityColor)),
                    ],
                  ),
                  Column(
                    children: [
                      Text('净收入', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('$priceSign¥${totalPrice.toStringAsFixed(2)}', 
                           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: priceColor)),
                    ],
                  ),
                ],
              ),
            ),
          
          records.isEmpty 
              ? Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.table_chart, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          '暂无交易数据',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.grey[300],
                          dataTableTheme: DataTableThemeData(
                            headingRowColor: MaterialStateProperty.all(Colors.purple[50]),
                            dataRowColor: MaterialStateProperty.resolveWith<Color>(
                              (Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected))
                                  return Colors.purple[100]!;
                                return states.contains(MaterialState.hovered)
                                    ? Colors.grey[100]!
                                    : Colors.white;
                              },
                            ),
                          ),
                        ),
                        child: DataTable(
                          headingTextStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.purple[800],
                          ),
                          dataTextStyle: TextStyle(
                            color: Colors.black87,
                            fontSize: 13,
                          ),
                          horizontalMargin: 16,
                          columnSpacing: 20,
                          showCheckboxColumn: false,
                          dividerThickness: 1,
                          columns: [
                            DataColumn(label: Text('日期')),
                            DataColumn(label: Text('类型')),
                            DataColumn(label: Text('产品')),
                            DataColumn(label: Text('数量')),
                            DataColumn(label: Text('单位')),
                            DataColumn(label: Text('客户')),
                            DataColumn(label: Text('金额')),
                            DataColumn(label: Text('备注')),
                          ],
                          rows: records.map((record) {
                            final customer = customers.firstWhere(
                              (c) => c['id'] == record['customerId'],
                              orElse: () => {'name': '未知客户'},
                            );
                            final product = products.firstWhere(
                              (p) => p['name'] == record['productName'],
                              orElse: () => {'unit': ''},
                            );
                            
                            // 设置颜色，销售为绿色，退货为红色
                            Color textColor = record['type'] == '销售' ? Colors.green : Colors.red;
                            
                            // 根据类型决定金额正负
                            String amount = record['type'] == '销售' 
                                ? record['totalPrice'].toString() 
                                : '-${record['totalPrice']}';
                            
                            // 根据类型决定数量正负
                            String quantity = record['type'] == '销售'
                                ? _formatNumber(record['quantity'])
                                : '-${_formatNumber(record['quantity'])}';
                            
                            return DataRow(
                              cells: [
                                DataCell(Text(record['date'])),
                                DataCell(
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: record['type'] == '销售' 
                                          ? Colors.green[50] 
                                          : Colors.red[50],
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: record['type'] == '销售' 
                                            ? Colors.green[300]! 
                                            : Colors.red[300]!,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      record['type'],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(Text(record['productName'])),
                                DataCell(
                                  Text(
                                    quantity,
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                ),
                                DataCell(Text(product['unit'])),
                                DataCell(Text(customer['name'])),
                                DataCell(
                                  Text(
                                    amount,
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataCell(Text(record['note'] ?? '')),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
          FooterWidget(),
        ],
      ),
    );
  }
} 