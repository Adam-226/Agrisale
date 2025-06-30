// lib/screens/purchase_report_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';

class PurchaseReportScreen extends StatefulWidget {
  @override
  _PurchaseReportScreenState createState() => _PurchaseReportScreenState();
}

class _PurchaseReportScreenState extends State<PurchaseReportScreen> {
  List<Map<String, dynamic>> _allPurchases = []; // 存储所有采购记录
  List<Map<String, dynamic>> _purchases = []; // 存储筛选后的采购记录
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _products = [];
  bool _isDescending = true; // 默认按时间倒序排列
  
  // 筛选条件
  String? _selectedProductName;
  int? _selectedSupplierId;
  DateTime? _startDate;
  DateTime? _endDate;
  
  // 统计数据
  int _totalQuantity = 0;
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
      _isDescending = prefs.getBool('purchases_sort_descending') ?? true;
    });
  }

  Future<void> _saveSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('purchases_sort_descending', _isDescending);
  }

  Future<void> _fetchData() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final orderBy = _isDescending ? 'purchaseDate DESC' : 'purchaseDate ASC';
        // 只获取当前用户的数据
        final purchases = await db.query('purchases', where: 'userId = ?', whereArgs: [userId], orderBy: orderBy);
        final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _allPurchases = purchases;
          _suppliers = suppliers;
          _products = products;
          _applyFilters(); // 应用筛选
        });
      }
    }
  }
  
  // 应用筛选条件
  void _applyFilters() {
    List<Map<String, dynamic>> filteredPurchases = List.from(_allPurchases);
    
    // 按产品名称筛选
    if (_selectedProductName != null) {
      filteredPurchases = filteredPurchases.where(
        (purchase) => purchase['productName'] == _selectedProductName
      ).toList();
    }
    
    // 按供应商筛选
    if (_selectedSupplierId != null) {
      filteredPurchases = filteredPurchases.where(
        (purchase) => purchase['supplierId'] == _selectedSupplierId
      ).toList();
    }
    
    // 按日期范围筛选
    if (_startDate != null) {
      filteredPurchases = filteredPurchases.where((purchase) {
        final purchaseDate = DateTime.parse(purchase['purchaseDate']);
        return purchaseDate.isAfter(_startDate!) || 
               purchaseDate.isAtSameMomentAs(_startDate!);
      }).toList();
    }
    
    if (_endDate != null) {
      final endDatePlusOne = _endDate!.add(Duration(days: 1)); // 包含结束日期
      filteredPurchases = filteredPurchases.where((purchase) {
        final purchaseDate = DateTime.parse(purchase['purchaseDate']);
        return purchaseDate.isBefore(endDatePlusOne);
      }).toList();
    }
    
    // 计算总量和总进价
    _calculateTotals(filteredPurchases);
    
    setState(() {
      _purchases = filteredPurchases;
    });
  }
  
  // 计算总量和总进价
  void _calculateTotals(List<Map<String, dynamic>> filteredPurchases) {
    int totalQuantity = 0;
    double totalPrice = 0.0;
    
    for (var purchase in filteredPurchases) {
      totalQuantity += purchase['quantity'] as int;
      totalPrice += (purchase['totalPurchasePrice'] as num).toDouble();
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
      _selectedSupplierId = null;
      _startDate = null;
      _endDate = null;
      _purchases = _allPurchases;
      _calculateTotals(_purchases);
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
        builder: (context) => PurchaseTableScreen(
          purchases: _purchases,
          suppliers: _suppliers,
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
                leading: Icon(Icons.business, color: Colors.orange),
                title: Text('按供应商筛选'),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showSupplierSelectionDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.date_range, color: Colors.blue),
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
           _selectedSupplierId != null || 
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
            child: ListView.builder(
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
  
  // 选择供应商对话框
  Future<void> _showSupplierSelectionDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('选择供应商'),
          content: Container(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suppliers.length,
              itemBuilder: (context, index) {
                final supplier = _suppliers[index];
                return ListTile(
                  title: Text(supplier['name']),
                  onTap: () {
                    setState(() {
                      _selectedSupplierId = supplier['id'];
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
              primary: Colors.green,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('采购报告', style: TextStyle(
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
          if (_purchases.isNotEmpty && _hasFilters())
            _buildSummaryCard(),
            
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.date_range, color: Colors.green[700], size: 20),
                SizedBox(width: 8),
                Text(
                  '采购记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
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
            child: _purchases.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assessment, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          _allPurchases.isEmpty ? '暂无采购记录' : '没有符合条件的记录',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _allPurchases.isEmpty ? '添加采购记录后会显示在这里' : '请尝试更改筛选条件',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                        if (!_allPurchases.isEmpty)
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
                  )
                : RefreshIndicator(
                    onRefresh: _fetchData,
            child: ListView.builder(
              itemCount: _purchases.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                final purchase = _purchases[index];
                final supplier = _suppliers.firstWhere(
                      (s) => s['id'] == purchase['supplierId'],
                  orElse: () => {'name': '未知供应商'},
                );
                final product = _products.firstWhere(
                      (p) => p['name'] == purchase['productName'],
                  orElse: () => {'unit': ''},
                );
                        
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
                                    Text(
                                      purchase['purchaseDate'],
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    Text(
                                      '¥ ${purchase['totalPurchasePrice']}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.green[700],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Text(
                                  purchase['productName'],
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
                                      '数量: ${purchase['quantity']} ${product['unit']}',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    SizedBox(width: 16),
                                    Icon(Icons.business, 
                                         size: 14, 
                                         color: Colors.orange[700]),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '供应商: ${supplier['name']}',
                                        style: TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (purchase['note'] != null && purchase['note'].toString().isNotEmpty)
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
                                            '备注: ${purchase['note']}',
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
      color: Colors.blue[50],
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
                if (_selectedSupplierId != null)
                  Chip(
                    label: Text('供应商: ${_suppliers.firstWhere(
                      (s) => s['id'] == _selectedSupplierId,
                      orElse: () => {'name': '未知'}
                    )['name']}'),
                    deleteIcon: Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedSupplierId = null;
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
                    backgroundColor: Colors.blue[100],
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
    
    return Card(
      margin: EdgeInsets.all(8),
      color: Colors.green[50],
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
                color: Colors.green[800],
              ),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('总记录数: ${_purchases.length}'),
                Text('总数量: $_totalQuantity ${_selectedProductName != null ? productUnit : ""}'),
              ],
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('总进价: ¥${_totalPrice.toStringAsFixed(2)}'),
                if (_selectedProductName != null && _totalQuantity > 0)
                  Text('平均单价: ¥${(_totalPrice / _totalQuantity).toStringAsFixed(2)}/${productUnit}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class PurchaseTableScreen extends StatelessWidget {
  final List<Map<String, dynamic>> purchases;
  final List<Map<String, dynamic>> suppliers;
  final List<Map<String, dynamic>> products;
  final int totalQuantity;
  final double totalPrice;

  PurchaseTableScreen({
    required this.purchases,
    required this.suppliers,
    required this.products,
    required this.totalQuantity,
    required this.totalPrice,
  });

  Future<void> _exportToCSV(BuildContext context) async {
    String csvData = '日期,产品,数量,单位,供应商,总进价,备注\n';
    for (var purchase in purchases) {
      final supplier = suppliers.firstWhere(
            (s) => s['id'] == purchase['supplierId'],
        orElse: () => {'name': '未知供应商'},
      );
      final product = products.firstWhere(
            (p) => p['name'] == purchase['productName'],
        orElse: () => {'unit': ''},
      );
      csvData += '${purchase['purchaseDate']},${purchase['productName']},${purchase['quantity']},${product['unit']},${supplier['name']},${purchase['totalPurchasePrice']},${purchase['note'] ?? ''}\n';
    }
    
    // 添加统计信息
    csvData += '\n总计,,,,,\n';
    csvData += '记录数,${purchases.length}\n';
    csvData += '总数量,${totalQuantity}\n';
    csvData += '总进价,${totalPrice.toStringAsFixed(2)}\n';

    if (Platform.isMacOS) {
      // macOS 使用 file_picker 让用户选择保存位置
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '保存采购报告',
        fileName: 'purchase_report.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(csvData);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出成功: $outputFile')),
        );
      }
      return;
    }

    String path;
    if (Platform.isAndroid) {
      // 请求存储权限
      if (await Permission.storage.request().isGranted) {
        final directory = Directory('/storage/emulated/0/Download');
        path = '${directory.path}/purchase_report.csv';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('存储权限被拒绝')),
        );
        return;
      }
    } else {
      // iOS 和其他平台使用应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/purchase_report.csv';
    }

    final file = File(path);
    await file.writeAsString(csvData);

    if (Platform.isAndroid) {
      // Android 直接保存到 Download 目录，提示用户
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出成功: $path')),
      );
    } else {
      // iOS 和其他平台通过分享让用户选择保存位置
      await Share.shareFiles([file.path], text: '采购报告 CSV 文件');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('采购报告表格', style: TextStyle(
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
            color: Colors.green[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.green[700], size: 16),
                SizedBox(width: 8),
          Expanded(
                  child: Text(
                    '横向和纵向滑动可查看更多数据，点击右上角图标可导出CSV文件',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 添加统计摘要
          if (purchases.isNotEmpty)
            Container(
              padding: EdgeInsets.all(12),
              color: Colors.green[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text('记录数', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('${purchases.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      Text('总数量', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('$totalQuantity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      Text('总进价', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('¥${totalPrice.toStringAsFixed(2)}', 
                           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[700])),
                    ],
                  ),
                ],
              ),
            ),
          
          purchases.isEmpty 
              ? Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.table_chart, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          '暂无采购数据',
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
                            headingRowColor: MaterialStateProperty.all(Colors.green[50]),
                            dataRowColor: MaterialStateProperty.resolveWith<Color>(
                              (Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected))
                                  return Colors.green[100]!;
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
                            color: Colors.green[800],
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
                  DataColumn(label: Text('产品')),
                  DataColumn(label: Text('数量')),
                  DataColumn(label: Text('单位')),
                  DataColumn(label: Text('供应商')),
                  DataColumn(label: Text('总进价')),
                  DataColumn(label: Text('备注')),
                ],
                rows: purchases.map((purchase) {
                  final supplier = suppliers.firstWhere(
                        (s) => s['id'] == purchase['supplierId'],
                    orElse: () => {'name': '未知供应商'},
                  );
                  final product = products.firstWhere(
                        (p) => p['name'] == purchase['productName'],
                    orElse: () => {'unit': ''},
                  );
                            return DataRow(
                              cells: [
                    DataCell(Text(purchase['purchaseDate'])),
                    DataCell(Text(purchase['productName'])),
                    DataCell(Text(purchase['quantity'].toString())),
                    DataCell(Text(product['unit'])),
                    DataCell(Text(supplier['name'])),
                                DataCell(
                                  Text(
                                    purchase['totalPurchasePrice'].toString(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ),
                    DataCell(Text(purchase['note'] ?? '')),
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