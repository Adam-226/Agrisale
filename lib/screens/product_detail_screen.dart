import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  ProductDetailScreen({required this.product});

  @override
  _ProductDetailScreenState createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  List<Map<String, dynamic>> _allRecords = []; // 存储所有记录
  List<Map<String, dynamic>> _filteredRecords = []; // 存储筛选后的记录
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _customers = [];
  bool _isDescending = true; // 默认按时间倒序排列
  bool _isSummaryExpanded = true; // 汇总信息是否展开
  
  // 交易类型排序顺序，数字越小越靠前
  Map<String, int> _typeOrderMap = {
    '采购': 1,
    '销售': 2,
    '退货': 3,
  };

  // 汇总数据
  int _purchaseQuantity = 0;
  double _purchaseAmount = 0.0;
  int _saleQuantity = 0;
  double _saleAmount = 0.0;
  int _returnQuantity = 0;
  double _returnAmount = 0.0;
  int _currentStock = 0;

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
    _fetchData();
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDescending = prefs.getBool('product_detail_sort_descending') ?? true;
    });
  }

  Future<void> _saveSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('product_detail_sort_descending', _isDescending);
  }

  void _toggleSortOrder() {
    setState(() {
      _isDescending = !_isDescending;
      _saveSortPreference();
      _sortRecords();
    });
  }

  void _sortRecords() {
    _filteredRecords.sort((a, b) {
      int result;
      
      // 一级排序：按日期
      result = _isDescending
          ? b['date'].toString().compareTo(a['date'].toString())
          : a['date'].toString().compareTo(b['date'].toString());
      
      // 如果日期相同，则按交易类型排序
      if (result == 0) {
        final aTypeOrder = _typeOrderMap[a['recordType']] ?? 99;
        final bTypeOrder = _typeOrderMap[b['recordType']] ?? 99;
        result = aTypeOrder.compareTo(bTypeOrder);
      }
      
      return result;
    });
    setState(() {});
  }

  // 更改交易类型排序顺序
  void _showTypeOrderDialog() {
    final List<String> types = ['采购', '销售', '退货'];
    final List<int> positions = [1, 2, 3]; // 可选位置：第一、第二、第三
    Map<String, int> tempTypeOrderMap = Map.from(_typeOrderMap);
    
    // 为选择器准备当前位置数据
    Map<String, int> currentPositions = {};
    types.forEach((type) {
      currentPositions[type] = tempTypeOrderMap[type] ?? 99;
    });
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('设置交易类型顺序'),
            content: Container(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('请为每种交易类型选择显示顺序：', style: TextStyle(fontSize: 14)),
                  SizedBox(height: 16),
                  ...types.map((type) {
                    Color typeColor = type == '采购' 
                      ? Colors.blue 
                      : (type == '销售' ? Colors.green : Colors.red);
                    IconData typeIcon = type == '采购' 
                      ? Icons.arrow_downward 
                      : (type == '销售' ? Icons.arrow_upward : Icons.compare_arrows);
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Icon(typeIcon, color: typeColor),
                          SizedBox(width: 8),
                          Text(type, style: TextStyle(fontWeight: FontWeight.bold)),
                          Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: DropdownButton<int>(
                              value: currentPositions[type],
                              underline: SizedBox(),
                              items: positions.map((position) {
                                return DropdownMenuItem<int>(
                                  value: position,
                                  child: Text('第$position位'),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    // 如果有其他类型已经占用了这个位置，交换它们的位置
                                    String? typeAtSamePosition;
                                    currentPositions.forEach((t, p) {
                                      if (p == value && t != type) {
                                        typeAtSamePosition = t;
                                      }
                                    });
                                    
                                    if (typeAtSamePosition != null) {
                                      currentPositions[typeAtSamePosition!] = currentPositions[type]!;
                                    }
                                    
                                    currentPositions[type] = value;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  // 应用新的排序顺序
                  setState(() {
                    types.forEach((type) {
                      tempTypeOrderMap[type] = currentPositions[type]!;
                    });
                    _typeOrderMap = tempTypeOrderMap;
                  });
                  Navigator.of(context).pop();
                  _sortRecords(); // 重新排序
                },
                child: Text('确定'),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _fetchData() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final productName = widget.product['name'];
        
        // 获取当前用户的采购数据
        final purchases = await db.rawQuery('''
          SELECT 
            purchaseDate AS date, 
            productName, 
            quantity, 
            supplierId AS partnerId,
            totalPurchasePrice AS totalPrice,
            note,
            'purchase' AS recordType
          FROM purchases
          WHERE productName = ? AND userId = ?
        ''', [productName, userId]);

        // 获取当前用户的销售数据
        final sales = await db.rawQuery('''
          SELECT 
            saleDate AS date, 
            productName, 
            quantity, 
            customerId AS partnerId, 
            totalSalePrice AS totalPrice,
            note,
            'sale' AS recordType
          FROM sales
          WHERE productName = ? AND userId = ?
        ''', [productName, userId]);

        // 获取当前用户的退货数据
        final returns = await db.rawQuery('''
          SELECT 
            returnDate AS date, 
            productName, 
            quantity, 
            customerId AS partnerId, 
            totalReturnPrice AS totalPrice,
            note,
            'return' AS recordType
          FROM returns
          WHERE productName = ? AND userId = ?
        ''', [productName, userId]);

        // 获取当前用户的供应商和客户数据
        final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        final customers = await db.query('customers', where: 'userId = ?', whereArgs: [userId]);

    // 合并所有记录
    List<Map<String, dynamic>> allRecords = [];
    
    // 添加采购数据
    for (var purchase in purchases) {
      final supplier = suppliers.firstWhere(
        (s) => s['id'] == purchase['partnerId'],
        orElse: () => {'name': '未知供应商'},
      );
      
      allRecords.add({
        'date': purchase['date'],
        'productName': purchase['productName'],
        'quantity': purchase['quantity'],
        'partnerId': purchase['partnerId'],
        'partnerName': supplier['name'],
        'partnerType': 'supplier',
        'totalPrice': purchase['totalPrice'],
        'note': purchase['note'],
        'recordType': '采购',
        'valueSign': 1, // 正值
      });
    }
    
    // 添加销售数据
    for (var sale in sales) {
      final customer = customers.firstWhere(
        (c) => c['id'] == sale['partnerId'],
        orElse: () => {'name': '未知客户'},
      );
      
      allRecords.add({
        'date': sale['date'],
        'productName': sale['productName'],
        'quantity': sale['quantity'],
        'partnerId': sale['partnerId'],
        'partnerName': customer['name'],
        'partnerType': 'customer',
        'totalPrice': sale['totalPrice'],
        'note': sale['note'],
        'recordType': '销售',
        'valueSign': -1, // 负值
      });
    }
    
    // 添加退货数据
    for (var returnItem in returns) {
      final customer = customers.firstWhere(
        (c) => c['id'] == returnItem['partnerId'],
        orElse: () => {'name': '未知客户'},
      );
      
      allRecords.add({
        'date': returnItem['date'],
        'productName': returnItem['productName'],
        'quantity': returnItem['quantity'],
        'partnerId': returnItem['partnerId'],
        'partnerName': customer['name'],
        'partnerType': 'customer',
        'totalPrice': returnItem['totalPrice'],
        'note': returnItem['note'],
        'recordType': '退货',
        'valueSign': 1, // 正值
      });
    }

    // 按日期和交易类型排序
    allRecords.sort((a, b) {
      int result;
      
      // 一级排序：按日期
      result = _isDescending
          ? b['date'].toString().compareTo(a['date'].toString())
          : a['date'].toString().compareTo(b['date'].toString());
      
      // 如果日期相同，则按交易类型排序
      if (result == 0) {
        final aTypeOrder = _typeOrderMap[a['recordType']] ?? 99;
        final bTypeOrder = _typeOrderMap[b['recordType']] ?? 99;
        result = aTypeOrder.compareTo(bTypeOrder);
      }
      
      return result;
    });

    // 计算汇总数据
    _calculateSummary(allRecords);

        setState(() {
          _allRecords = allRecords;
          _filteredRecords = allRecords;
          _suppliers = suppliers;
          _customers = customers;
          _currentStock = widget.product['stock'];
        });
      }
    }
  }

  void _calculateSummary(List<Map<String, dynamic>> records) {
    int purchaseQuantity = 0;
    double purchaseAmount = 0.0;
    int saleQuantity = 0;
    double saleAmount = 0.0;
    int returnQuantity = 0;
    double returnAmount = 0.0;

    for (var record in records) {
      if (record['recordType'] == '采购') {
        purchaseQuantity += record['quantity'] as int;
        purchaseAmount += (record['totalPrice'] as num).toDouble();
      } else if (record['recordType'] == '销售') {
        saleQuantity += record['quantity'] as int;
        saleAmount += (record['totalPrice'] as num).toDouble();
      } else if (record['recordType'] == '退货') {
        returnQuantity += record['quantity'] as int;
        returnAmount += (record['totalPrice'] as num).toDouble();
      }
    }

    setState(() {
      _purchaseQuantity = purchaseQuantity;
      _purchaseAmount = purchaseAmount;
      _saleQuantity = saleQuantity;
      _saleAmount = saleAmount;
      _returnQuantity = returnQuantity;
      _returnAmount = returnAmount;
    });
  }

  // 导出为CSV文件
  Future<void> _exportToCSV() async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    String csvData = '产品详情报告 - 用户: $username\n';
    csvData += '导出时间: ${DateTime.now().toString().substring(0, 19)}\n';
    csvData += '产品名称: ${widget.product['name']}\n\n';
    csvData += '日期,类型,产品,数量,单位,交易方,金额,备注\n';
    
    for (var record in _filteredRecords) {
      // 设置数量和金额的符号
      String quantitySign = record['recordType'] == '销售' ? '-' : '+';
      String priceSign = record['recordType'] == '销售' ? '+' : '-';
      
      csvData += '${record['date']},${record['recordType']},${record['productName']},$quantitySign${record['quantity']},${widget.product['unit']},${record['partnerName']},$priceSign${record['totalPrice']},${record['note'] ?? ''}\n';
    }
    
    // 添加汇总信息
    csvData += '\n汇总信息,,,,,\n';
    csvData += '当前库存,${_currentStock},${widget.product['unit']}\n';
    csvData += '采购总量,$_purchaseQuantity,${widget.product['unit']}\n';
    csvData += '销售总量,$_saleQuantity,${widget.product['unit']}\n';
    csvData += '退货总量,$_returnQuantity,${widget.product['unit']}\n';
    csvData += '采购总额,-¥${_purchaseAmount.toStringAsFixed(2)}\n';
    csvData += '销售总额,+¥${_saleAmount.toStringAsFixed(2)}\n';
    csvData += '退货总额,-¥${_returnAmount.toStringAsFixed(2)}\n';
    csvData += '净收益,¥${(_saleAmount - _purchaseAmount - _returnAmount).toStringAsFixed(2)}\n';

    if (Platform.isMacOS) {
      // macOS: 使用 file_picker 让用户选择保存位置
      String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存产品详情报告',
        fileName: 'product_${widget.product['name']}_report.csv',
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
        path = '${directory.path}/product_${widget.product['name']}_report.csv';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('存储权限被拒绝')),
        );
        return;
      }
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/product_${widget.product['name']}_report.csv';
    } else {
      // 其他平台使用应用文档目录作为后备方案
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/product_${widget.product['name']}_report.csv';
    }

    final file = File(path);
    await file.writeAsString(csvData);

    if (Platform.isIOS) {
      // iOS 让用户手动选择存储位置
      await Share.shareFiles([file.path], text: '${widget.product['name']} 产品报告 CSV 文件');
    } else {
      // Android 直接存入 Download 目录，并提示用户
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出成功: $path')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.product['name']}的记录', 
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )
        ),
        actions: [
          // 添加类型排序按钮
          IconButton(
            icon: Icon(Icons.swap_vert),
            tooltip: '设置交易类型排序',
            onPressed: _showTypeOrderDialog,
          ),
          IconButton(
            icon: Icon(_isDescending ? Icons.arrow_downward : Icons.arrow_upward),
            tooltip: '切换排序',
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
          // 产品信息和汇总信息合并卡片
          _buildCombinedInfoCard(),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.list_alt, color: Colors.blue[700], size: 20),
                SizedBox(width: 8),
                Text(
                  '交易记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
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
          
          _filteredRecords.isEmpty 
            ? Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2, size: 64, color: Colors.grey[400]),
                      SizedBox(height: 16),
                      Text(
                        '暂无交易记录',
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
                          DataColumn(label: Text('类型')),
                          DataColumn(label: Text('数量')),
                          DataColumn(label: Text('单位')),
                          DataColumn(label: Text('交易方')),
                          DataColumn(label: Text('金额')),
                          DataColumn(label: Text('备注')),
                        ],
                        rows: _filteredRecords.map((record) {
                          // 设置颜色
                          Color typeColor;
                          if (record['recordType'] == '采购') {
                            typeColor = Colors.blue;
                          } else if (record['recordType'] == '销售') {
                            typeColor = Colors.green;
                          } else { // 退货
                            typeColor = Colors.red;
                          }
                          
                          // 设置数量和金额的符号
                          String quantitySign = record['recordType'] == '销售' ? '-' : '+';
                          String priceSign = record['recordType'] == '销售' ? '+' : '-';
                          
                          return DataRow(
                            cells: [
                              DataCell(Text(record['date'])),
                              DataCell(
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: typeColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: typeColor.withOpacity(0.5),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    record['recordType'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: typeColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '$quantitySign${record['quantity']}',
                                  style: TextStyle(
                                    color: typeColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              ),
                              DataCell(
                                Text(
                                  widget.product['unit'],
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                  ),
                                )
                              ),
                              DataCell(Text(record['partnerName'])),
                              DataCell(
                                Text(
                                  '$priceSign¥${record['totalPrice']}',
                                  style: TextStyle(
                                    color: typeColor,
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

  // 合并产品信息和汇总信息卡片
  Widget _buildCombinedInfoCard() {
    // 计算毛利
    double grossProfit = _saleAmount - _purchaseAmount - _returnAmount;
    
    return Card(
      margin: EdgeInsets.all(8),
      elevation: 2,
      color: Colors.blue[50],
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 产品基本信息和汇总信息标题放在同一行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 产品信息
                Row(
                  children: [
                    Icon(Icons.inventory_2, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Text(
                      '${widget.product['name']} (${widget.product['unit']})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
                // 汇总信息标题和折叠按钮
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
              
              // 当前库存和记录数
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('当前库存', '$_currentStock ${widget.product['unit']}', Colors.blue),
                  _buildSummaryItem('记录总数', '${_filteredRecords.length}', Colors.purple),
                ],
              ),
              SizedBox(height: 12),
              
              // 数量汇总 - 横向布局
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('采购总量', '+$_purchaseQuantity ${widget.product['unit']}', Colors.blue),
                  _buildSummaryItem('销售总量', '-$_saleQuantity ${widget.product['unit']}', Colors.green),
                  _buildSummaryItem('退货总量', '+$_returnQuantity ${widget.product['unit']}', Colors.red),
                ],
              ),
              SizedBox(height: 12),
              
              // 金额汇总 - 横向布局
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('采购总额', '-¥${_purchaseAmount.toStringAsFixed(2)}', Colors.blue),
                  _buildSummaryItem('销售总额', '+¥${_saleAmount.toStringAsFixed(2)}', Colors.green),
                  _buildSummaryItem('退货总额', '-¥${_returnAmount.toStringAsFixed(2)}', Colors.red),
                ],
              ),
              
              Divider(height: 16, thickness: 1),
              
              // 净收益
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('净收益: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '${grossProfit >= 0 ? '+' : ''}¥${grossProfit.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: grossProfit >= 0 ? Colors.green : Colors.red,
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