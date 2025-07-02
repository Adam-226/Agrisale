// lib/screens/supplier_records_screen.dart

import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';

class SupplierRecordsScreen extends StatefulWidget {
  final int supplierId;
  final String supplierName;

  SupplierRecordsScreen({required this.supplierId, required this.supplierName});

  @override
  _SupplierRecordsScreenState createState() => _SupplierRecordsScreenState();
}

class _SupplierRecordsScreenState extends State<SupplierRecordsScreen> {
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _products = [];
  bool _isDescending = true;
  String? _selectedProduct = '所有产品'; // 产品筛选
  bool _isSummaryExpanded = true; // 汇总信息是否展开
  
  // 汇总数据
  double _totalQuantity = 0.0;
  double _totalAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _fetchRecords();
  }

  // 格式化数字方法：整数显示为整数，小数显示为小数
  String _formatNumber(dynamic number) {
    if (number == null) return '0';
    double value = number is double ? number : double.tryParse(number.toString()) ?? 0.0;
    if (value == value.floor()) {
      return value.toInt().toString();
    } else {
      return value.toString();
    }
  }

  Future<void> _fetchProducts() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _products = products;
        });
      }
    }
  }

  Future<void> _fetchRecords() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final orderBy = _isDescending ? 'DESC' : 'ASC';
        
        // 构建产品筛选条件
        String productFilter = _selectedProduct != null && _selectedProduct != '所有产品'
            ? "AND productName = '$_selectedProduct'"
            : '';

        // 获取当前用户的采购记录
        final purchases = await db.rawQuery('''
          SELECT * FROM purchases 
          WHERE supplierId = ? AND userId = ? $productFilter
          ORDER BY purchaseDate $orderBy
        ''', [widget.supplierId, userId]);

        // 获取当前用户的产品信息
        final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);

        // 将单位信息添加到采购记录中
        final purchasesWithUnits = purchases.map((purchase) {
          final product = products.firstWhere(
                (p) => p['name'] == purchase['productName'],
            orElse: () => {'unit': ''},
          );
          return {
            ...purchase,
            'unit': product['unit'],
          };
        }).toList();

        // 计算汇总数据
        _calculateSummary(purchasesWithUnits);

        setState(() {
          _purchases = purchasesWithUnits;
        });
      }
    }
  }

  void _calculateSummary(List<Map<String, dynamic>> purchases) {
    double totalQuantity = 0.0;
    double totalAmount = 0.0;

    for (var purchase in purchases) {
      totalQuantity += (purchase['quantity'] as num).toDouble();
      totalAmount += (purchase['totalPurchasePrice'] as num).toDouble();
    }

    setState(() {
      _totalQuantity = totalQuantity;
      _totalAmount = totalAmount;
    });
  }

  Future<void> _exportToCSV() async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    List<List<dynamic>> rows = [];
    // 添加用户信息和导出时间
    rows.add(['供应商采购记录 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    rows.add(['供应商: ${widget.supplierName}']);
    rows.add(['产品筛选: $_selectedProduct']);
    rows.add([]); // 空行
    // 修改表头为中文
    rows.add(['日期', '产品', '数量', '单位', '总价', '备注']);

    for (var purchase in _purchases) {
      rows.add([
        purchase['purchaseDate'],
        purchase['productName'],
        _formatNumber(purchase['quantity']),
        purchase['unit'] ?? '',
        purchase['totalPurchasePrice'],
        purchase['note'] ?? ''
      ]);
    }

    // 添加总计行
    rows.add([]);
    rows.add(['总计', '', 
              _formatNumber(_totalQuantity), 
              _selectedProduct != '所有产品' 
                  ? (_products.firstWhere((p) => p['name'] == _selectedProduct, orElse: () => {'unit': ''})['unit'] ?? '')
                  : '', 
              _totalAmount.toStringAsFixed(2), 
              '']);

    String csv = const ListToCsvConverter().convert(rows);

    if (Platform.isMacOS || Platform.isWindows) {
      // macOS 和 Windows: 使用 file_picker 让用户选择保存位置
      String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存供应商采购记录',
        fileName: '${widget.supplierName}_purchases.csv',
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
        path = '${directory.path}/${widget.supplierName}_purchases.csv';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('存储权限被拒绝')),
        );
        return;
      }
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/${widget.supplierName}_purchases.csv';
    } else {
      // 其他平台使用应用文档目录作为后备方案
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/${widget.supplierName}_purchases.csv';
    }

    final file = File(path);
    await file.writeAsString(csv);

    if (Platform.isIOS) {
      // iOS 让用户手动选择存储位置
      await Share.shareFiles([file.path], text: '${widget.supplierName}的采购记录 CSV 文件');
    } else {
      // Android 直接存入 Download 目录，并提示用户
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出成功: $path')),
      );
    }
  }

  void _toggleSortOrder() {
    setState(() {
      _isDescending = !_isDescending;
      _fetchRecords();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.supplierName}的采购记录', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
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
          // 产品筛选条件
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.filter_alt, color: Colors.blue[700], size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[300]!),
                        color: Colors.white,
                      ),
                      child: DropdownButton<String>(
                        hint: Text('选择产品', style: TextStyle(color: Colors.black87)),
                        value: _selectedProduct,
                        isExpanded: true,
                        icon: Icon(Icons.arrow_drop_down, color: Colors.blue[700]),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedProduct = newValue;
                            _fetchRecords();
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
              ],
            ),
          ),

          // 汇总信息卡片
          _buildSummaryCard(),

          Container(
            padding: EdgeInsets.all(12),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                SizedBox(width: 8),
          Expanded(
                  child: Text(
                    '横向和纵向滑动可查看更多数据，点击右上角图标可导出CSV文件',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.business,
                    color: Colors.blue[800],
                    size: 16,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '供应商采购记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '共 ${_purchases.length} 条记录',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
          _purchases.isEmpty
              ? Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          '暂无采购记录',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _selectedProduct == '所有产品' 
                              ? '该供应商还没有采购记录'
                              : '该供应商还没有采购 $_selectedProduct 的记录',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
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
                            headingRowColor: MaterialStateProperty.all(Colors.blue[50]),
                            dataRowColor: MaterialStateProperty.resolveWith<Color>(
                              (Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected))
                                  return Colors.blue[100]!;
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
                            color: Colors.blue[800],
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
                  DataColumn(label: Text('总价')),
                  DataColumn(label: Text('备注')),
                ],
                          rows: [
                            // 数据行
                            ..._purchases.map((purchase) => DataRow(cells: [
                  DataCell(Text(purchase['purchaseDate'])),
                  DataCell(Text(purchase['productName'])),
                              DataCell(Text(_formatNumber(purchase['quantity']))),
                  DataCell(Text(purchase['unit'] ?? '')),
                            DataCell(
                              Text(
                                purchase['totalPurchasePrice'].toString(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              )
                            ),
                            DataCell(
                              purchase['note'] != null && purchase['note'].toString().isNotEmpty
                                  ? Text(
                                      purchase['note'],
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey[700],
                                      ),
                                    )
                                  : Text(''),
                            ),
                ])).toList(),
                            
                            // 总计行
                            if (_purchases.isNotEmpty)
                              DataRow(
                                color: MaterialStateProperty.all(Colors.grey[100]),
                                cells: [
                                  DataCell(Text('')), // 日期列
                                  DataCell(
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blue[300]!, width: 1),
                                      ),
                                      child: Text(
                                        '总计',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue[800],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      _formatNumber(_totalQuantity),
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      _selectedProduct != '所有产品' 
                                          ? (_products.firstWhere((p) => p['name'] == _selectedProduct, orElse: () => {'unit': ''})['unit'] ?? '')
                                          : '',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '¥${_totalAmount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text('')), // 备注列
                                ],
                              ),
                          ],
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

  // 汇总信息卡片
  Widget _buildSummaryCard() {
    return Card(
      margin: EdgeInsets.all(8),
      elevation: 2,
      color: Colors.blue[50],
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 供应商信息和汇总信息标题
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.business, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Text(
                      '${widget.supplierName} - ${_selectedProduct ?? '所有产品'}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _isSummaryExpanded = !_isSummaryExpanded;
                    });
                  },
                  child: Row(
                    children: [
                      Text(
                        '汇总信息',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        _isSummaryExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 16,
                        color: Colors.blue[800],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isSummaryExpanded) ...[
              Divider(height: 16, thickness: 1),
              
              // 记录数和平均单价
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('采购记录数', '${_purchases.length}', Colors.purple),
                  _buildSummaryItem('平均单价', _totalQuantity > 0 ? '¥${(_totalAmount / _totalQuantity).toStringAsFixed(2)}' : '¥0.00', Colors.orange),
                ],
              ),
              SizedBox(height: 12),
              
              // 总数量和总金额
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('采购总量', '${_formatNumber(_totalQuantity)}', Colors.green),
                  _buildSummaryItem('采购总额', '¥${_totalAmount.toStringAsFixed(2)}', Colors.green),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}