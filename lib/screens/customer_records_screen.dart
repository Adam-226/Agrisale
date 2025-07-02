// lib/screens/customer_records_screen.dart

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

class CustomerRecordsScreen extends StatefulWidget {
  final int customerId;
  final String customerName;

  CustomerRecordsScreen({required this.customerId, required this.customerName});

  @override
  _CustomerRecordsScreenState createState() => _CustomerRecordsScreenState();
}

class _CustomerRecordsScreenState extends State<CustomerRecordsScreen> {
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _products = [];
  bool _isDescending = true;
  bool _salesFirst = true; // 控制购买在前还是退货在前
  String? _selectedProduct = '所有产品'; // 产品筛选
  bool _isSummaryExpanded = true; // 汇总信息是否展开
  
  // 汇总数据
  double _totalPurchaseQuantity = 0.0;
  double _totalPurchaseAmount = 0.0;
  double _totalReturnQuantity = 0.0;
  double _totalReturnAmount = 0.0;
  double _netQuantity = 0.0;
  double _netAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _fetchRecords();
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
        // 构建产品筛选条件
        String productFilter = _selectedProduct != null && _selectedProduct != '所有产品'
            ? "AND productName = '$_selectedProduct'"
            : '';

        // 获取当前用户的销售记录
        final sales = await db.rawQuery('''
          SELECT * FROM sales 
          WHERE customerId = ? AND userId = ? $productFilter
        ''', [widget.customerId, userId]);

        // 获取当前用户的退货记录
        final returns = await db.rawQuery('''
          SELECT * FROM returns 
          WHERE customerId = ? AND userId = ? $productFilter
        ''', [widget.customerId, userId]);

        // 获取当前用户的产品信息
        final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);

        // 合并购买和退货记录
        final combinedRecords = [
          ...sales.map((sale) {
            final product = products.firstWhere(
                  (p) => p['name'] == sale['productName'],
              orElse: () => {'unit': ''},
            );
            return {
              'date': sale['saleDate'] as String,
              'type': '购买',
              'productName': sale['productName'],
              'unit': product['unit'],
              'quantity': sale['quantity'],
              'totalPrice': sale['totalSalePrice'],
              'note': sale['note'] ?? '',
            };
          }),
          ...returns.map((returnItem) {
            final product = products.firstWhere(
                  (p) => p['name'] == returnItem['productName'],
              orElse: () => {'unit': ''},
            );
            return {
              'date': returnItem['returnDate'] as String,
              'type': '退货',
              'productName': returnItem['productName'],
              'unit': product['unit'],
              'quantity': returnItem['quantity'],
              'totalPrice': returnItem['totalReturnPrice'],
              'note': returnItem['note'] ?? '',
            };
          }),
        ];

        // 按日期和类型排序
        combinedRecords.sort((a, b) {
          int dateComparison = _isDescending
              ? (b['date'] as String).compareTo(a['date'] as String)
              : (a['date'] as String).compareTo(b['date'] as String);
          if (dateComparison != 0) return dateComparison;

          // 如果日期相同，根据类型排序
          if (_salesFirst) {
            return a['type'] == '购买' ? -1 : 1;
          } else {
            return a['type'] == '退货' ? -1 : 1;
          }
        });

        // 计算汇总数据
        _calculateSummary(combinedRecords);

        setState(() {
          _records = combinedRecords;
        });
      }
    }
  }

  void _calculateSummary(List<Map<String, dynamic>> records) {
    double purchaseQuantity = 0.0;
    double purchaseAmount = 0.0;
    double returnQuantity = 0.0;
    double returnAmount = 0.0;

    for (var record in records) {
      if (record['type'] == '购买') {
        purchaseQuantity += (record['quantity'] as num).toDouble();
        purchaseAmount += (record['totalPrice'] as num).toDouble();
      } else if (record['type'] == '退货') {
        returnQuantity += (record['quantity'] as num).toDouble();
        returnAmount += (record['totalPrice'] as num).toDouble();
      }
    }

    setState(() {
      _totalPurchaseQuantity = purchaseQuantity;
      _totalPurchaseAmount = purchaseAmount;
      _totalReturnQuantity = returnQuantity;
      _totalReturnAmount = returnAmount;
      _netQuantity = purchaseQuantity - returnQuantity;
      _netAmount = purchaseAmount - returnAmount;
    });
  }

  Future<void> _exportToCSV() async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    List<List<dynamic>> rows = [];
    // 添加用户信息和导出时间
    rows.add(['客户交易记录 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    rows.add(['客户: ${widget.customerName}']);
    rows.add(['产品筛选: $_selectedProduct']);
    rows.add([]); // 空行
    // 修改表头为中文
    rows.add(['日期', '类型', '产品', '数量', '单位', '金额', '备注']);

    for (var record in _records) {
      // 根据类型决定金额正负
      String amount = record['type'] == '购买' 
          ? record['totalPrice'].toString() 
          : '-${record['totalPrice']}';
      
      // 根据类型决定数量正负
      String quantity = record['type'] == '购买'
          ? _formatNumber(record['quantity'])
          : '-${_formatNumber(record['quantity'])}';
          
      rows.add([
        record['date'],
        record['type'],
        record['productName'],
        quantity,
        record['unit'],
        amount,
        record['note']
      ]);
    }

    // 添加总计行
    rows.add([]);
    rows.add(['总计', '', '', 
              _formatNumber(_netQuantity), 
              _selectedProduct != '所有产品' 
                  ? (_products.firstWhere((p) => p['name'] == _selectedProduct, orElse: () => {'unit': ''})['unit'] ?? '')
                  : '', 
              _netAmount.toStringAsFixed(2), 
              '']);

    String csv = const ListToCsvConverter().convert(rows);

    if (Platform.isMacOS || Platform.isWindows) {
      // macOS 和 Windows: 使用 file_picker 让用户选择保存位置
      String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存客户交易记录',
        fileName: '${widget.customerName}_records.csv',
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
        path = '${directory.path}/${widget.customerName}_records.csv';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('存储权限被拒绝')),
        );
        return;
      }
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/${widget.customerName}_records.csv';
    } else {
      // 其他平台使用应用文档目录作为后备方案
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/${widget.customerName}_records.csv';
    }

    final file = File(path);
    await file.writeAsString(csv);

    if (Platform.isIOS) {
      // iOS 让用户手动选择存储位置
      await Share.shareFiles([file.path], text: '${widget.customerName}的记录 CSV 文件');
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

  void _toggleSalesFirst() {
    setState(() {
      _salesFirst = !_salesFirst;
      _fetchRecords();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.customerName}的记录', style: TextStyle(
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
            icon: Icon(_salesFirst ? Icons.swap_vert : Icons.swap_vert),
            tooltip: _salesFirst ? '购买在前' : '退货在前',
            onPressed: _toggleSalesFirst,
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
            color: Colors.orange[50],
            child: Row(
              children: [
                Icon(Icons.filter_alt, color: Colors.orange[700], size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[300]!),
                        color: Colors.white,
                      ),
                      child: DropdownButton<String>(
                        hint: Text('选择产品', style: TextStyle(color: Colors.black87)),
                        value: _selectedProduct,
                        isExpanded: true,
                        icon: Icon(Icons.arrow_drop_down, color: Colors.orange[700]),
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
            color: Colors.orange[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[700], size: 16),
                SizedBox(width: 8),
          Expanded(
                  child: Text(
                    '横向和纵向滑动可查看更多数据，购买以绿色显示，退货以红色显示',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[800],
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
                CircleAvatar(
                  backgroundColor: Colors.orange[100],
                  radius: 14,
                  child: Text(
                    widget.customerName.isNotEmpty 
                        ? widget.customerName[0].toUpperCase() 
                        : '?',
                    style: TextStyle(
                      color: Colors.orange[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '客户交易记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
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
                    '共 ${_records.length} 条记录',
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
          _records.isEmpty 
              ? Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          '暂无交易记录',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _selectedProduct == '所有产品' 
                              ? '该客户还没有购买或退货记录'
                              : '该客户还没有购买或退货 $_selectedProduct 的记录',
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
                            headingRowColor: MaterialStateProperty.all(Colors.orange[50]),
                            dataRowColor: MaterialStateProperty.resolveWith<Color>(
                              (Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected))
                                  return Colors.orange[100]!;
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
                            color: Colors.orange[800],
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
                            DataColumn(label: Text('金额')),
                  DataColumn(label: Text('备注')),
                ],
                          rows: [
                            // 数据行
                            ..._records.map((record) {
                              // 设置颜色，购买为绿色，退货为红色
                              Color textColor = record['type'] == '购买' ? Colors.green : Colors.red;
                              
                              // 根据类型决定金额正负
                              String amount = record['type'] == '购买' 
                                  ? record['totalPrice'].toString() 
                                  : '-${record['totalPrice']}';
                              
                              // 根据类型决定数量显示格式
                              String quantity = record['type'] == '购买'
                                  ? _formatNumber(record['quantity'])
                                  : '-${_formatNumber(record['quantity'])}';
                                  
                              return DataRow(
                                cells: [
                    DataCell(Text(record['date'])),
                                  DataCell(
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: record['type'] == '购买' 
                                            ? Colors.green[50] 
                                            : Colors.red[50],
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: record['type'] == '购买' 
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
                    DataCell(Text(record['unit'] ?? '')),
                                  DataCell(
                                    Text(
                                      amount,
                                      style: TextStyle(
                                        color: textColor, 
                                        fontWeight: FontWeight.bold
                                      ),
                                    ),
                                  ),
                                DataCell(
                                  record['note'].toString().isNotEmpty
                                      ? Text(
                                          record['note'],
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey[700],
                                          ),
                                        )
                                      : Text(''),
                                ),
                              ],
                            );
                          }).toList(),
                            
                            // 总计行
                            if (_records.isNotEmpty)
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
                                  DataCell(Text('')), // 产品列
                                  DataCell(
                                    Text(
                                      '${_netQuantity >= 0 ? '+' : ''}${_formatNumber(_netQuantity)}',
                                      style: TextStyle(
                                        color: _netQuantity >= 0 ? Colors.green : Colors.red,
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
                                      '${_netAmount >= 0 ? '+' : ''}¥${_netAmount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: _netAmount >= 0 ? Colors.green : Colors.red,
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
      color: Colors.orange[50],
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 客户信息和汇总信息标题
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.person, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Text(
                      '${widget.customerName} - ${_selectedProduct ?? '所有产品'}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
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
                          color: Colors.orange[800],
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        _isSummaryExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 16,
                        color: Colors.orange[800],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isSummaryExpanded) ...[
              Divider(height: 16, thickness: 1),
              
              // 记录数和净值
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('交易记录数', '${_records.length}', Colors.purple),
                  _buildSummaryItem('净数量', '${_netQuantity >= 0 ? '+' : ''}${_formatNumber(_netQuantity)}', _netQuantity >= 0 ? Colors.green : Colors.red),
                ],
              ),
              SizedBox(height: 12),
              
              // 购买和退货数量汇总
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('购买总量', '+${_formatNumber(_totalPurchaseQuantity)}', Colors.green),
                  _buildSummaryItem('退货总量', '-${_formatNumber(_totalReturnQuantity)}', Colors.red),
                ],
              ),
              SizedBox(height: 12),
              
              // 购买和退货金额汇总
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('购买总额', '+¥${_totalPurchaseAmount.toStringAsFixed(2)}', Colors.green),
                  _buildSummaryItem('退货总额', '-¥${_totalReturnAmount.toStringAsFixed(2)}', Colors.red),
                ],
              ),
              
              Divider(height: 16, thickness: 1),
              
              // 净收入
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('净收入: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '${_netAmount >= 0 ? '+' : ''}¥${_netAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: _netAmount >= 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
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