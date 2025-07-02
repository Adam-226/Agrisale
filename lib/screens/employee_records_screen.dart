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

class EmployeeRecordsScreen extends StatefulWidget {
  final int employeeId;
  final String employeeName;

  EmployeeRecordsScreen({required this.employeeId, required this.employeeName});

  @override
  _EmployeeRecordsScreenState createState() => _EmployeeRecordsScreenState();
}

class _EmployeeRecordsScreenState extends State<EmployeeRecordsScreen> {
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _suppliers = [];
  bool _isDescending = true;
  bool _incomeFirst = true; // 控制进账在前还是汇款在前
  String? _selectedType = '所有类型'; // 类型筛选
  bool _isSummaryExpanded = true; // 汇总信息是否展开
  
  // 添加日期筛选相关变量
  DateTimeRange? _selectedDateRange;
  DateTime? _selectedSingleDate;
  String _dateFilterType = '所有日期'; // '所有日期', '单日', '日期范围'
  
  // 汇总数据
  double _totalIncomeAmount = 0.0;
  double _totalRemittanceAmount = 0.0;
  double _totalDiscountAmount = 0.0; // 添加总优惠金额
  double _netAmount = 0.0;
  int _incomeCount = 0;
  int _remittanceCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchCustomersAndSuppliers();
    _fetchRecords();
  }

  Future<void> _fetchCustomersAndSuppliers() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final customers = await db.query('customers', where: 'userId = ?', whereArgs: [userId]);
        final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _customers = customers;
          _suppliers = suppliers;
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
        List<Map<String, dynamic>> combinedRecords = [];

        // 获取进账记录
        if (_selectedType == '所有类型' || _selectedType == '进账') {
          String dateFilter = '';
          List<dynamic> dateParams = [widget.employeeId, userId];
          
          // 添加日期筛选条件
          if (_dateFilterType == '单日' && _selectedSingleDate != null) {
            dateFilter = 'AND i.incomeDate = ?';
            dateParams.add(_selectedSingleDate!.toIso8601String().split('T')[0]);
          } else if (_dateFilterType == '日期范围' && _selectedDateRange != null) {
            dateFilter = 'AND i.incomeDate >= ? AND i.incomeDate <= ?';
            dateParams.add(_selectedDateRange!.start.toIso8601String().split('T')[0]);
            dateParams.add(_selectedDateRange!.end.toIso8601String().split('T')[0]);
          }
          
          final incomes = await db.rawQuery('''
            SELECT i.*, c.name as customerName
            FROM income i
            LEFT JOIN customers c ON i.customerId = c.id
            WHERE i.employeeId = ? AND i.userId = ? $dateFilter
          ''', dateParams);

          combinedRecords.addAll(incomes.map((income) => {
            'date': income['incomeDate'] as String,
            'type': '进账',
            'relatedName': income['customerName'] ?? '未指定客户',
            'amount': income['amount'],
            'discount': income['discount'] ?? 0.0,
            'paymentMethod': income['paymentMethod'],
            'note': income['note'] ?? '',
            'id': income['id'],
          }));
        }

        // 获取汇款记录
        if (_selectedType == '所有类型' || _selectedType == '汇款') {
          String dateFilter = '';
          List<dynamic> dateParams = [widget.employeeId, userId];
          
          // 添加日期筛选条件
          if (_dateFilterType == '单日' && _selectedSingleDate != null) {
            dateFilter = 'AND r.remittanceDate = ?';
            dateParams.add(_selectedSingleDate!.toIso8601String().split('T')[0]);
          } else if (_dateFilterType == '日期范围' && _selectedDateRange != null) {
            dateFilter = 'AND r.remittanceDate >= ? AND r.remittanceDate <= ?';
            dateParams.add(_selectedDateRange!.start.toIso8601String().split('T')[0]);
            dateParams.add(_selectedDateRange!.end.toIso8601String().split('T')[0]);
          }
          
          final remittances = await db.rawQuery('''
            SELECT r.*, s.name as supplierName
            FROM remittance r
            LEFT JOIN suppliers s ON r.supplierId = s.id
            WHERE r.employeeId = ? AND r.userId = ? $dateFilter
          ''', dateParams);

          combinedRecords.addAll(remittances.map((remittance) => {
            'date': remittance['remittanceDate'] as String,
            'type': '汇款',
            'relatedName': remittance['supplierName'] ?? '未指定供应商',
            'amount': remittance['amount'],
            'discount': 0.0, // 汇款没有优惠
            'paymentMethod': remittance['paymentMethod'],
            'note': remittance['note'] ?? '',
            'id': remittance['id'],
          }));
        }

        // 按日期和类型排序
        combinedRecords.sort((a, b) {
          int dateComparison = _isDescending
              ? (b['date'] as String).compareTo(a['date'] as String)
              : (a['date'] as String).compareTo(b['date'] as String);
          if (dateComparison != 0) return dateComparison;

          // 如果日期相同，根据类型排序
          if (_incomeFirst) {
            return a['type'] == '进账' ? -1 : 1;
          } else {
            return a['type'] == '汇款' ? -1 : 1;
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
    double incomeAmount = 0.0;
    double remittanceAmount = 0.0;
    double discountAmount = 0.0; // 添加优惠金额计算
    int incomeCount = 0;
    int remittanceCount = 0;

    for (var record in records) {
      if (record['type'] == '进账') {
        incomeAmount += (record['amount'] as num).toDouble();
        discountAmount += (record['discount'] as num).toDouble(); // 累计优惠金额
        incomeCount++;
      } else if (record['type'] == '汇款') {
        remittanceAmount += (record['amount'] as num).toDouble();
        remittanceCount++;
      }
    }

    setState(() {
      _totalIncomeAmount = incomeAmount;
      _totalRemittanceAmount = remittanceAmount;
      _totalDiscountAmount = discountAmount; // 设置总优惠金额
      _netAmount = incomeAmount - remittanceAmount;
      _incomeCount = incomeCount;
      _remittanceCount = remittanceCount;
    });
  }

  Future<void> _exportToCSV() async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    List<List<dynamic>> rows = [];
    // 添加用户信息和导出时间
    rows.add(['员工业务记录 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    rows.add(['员工: ${widget.employeeName}']);
    rows.add(['类型筛选: $_selectedType']);
    
    // 添加日期筛选信息
    String dateFilterInfo = '日期筛选: $_dateFilterType';
    if (_dateFilterType == '单日' && _selectedSingleDate != null) {
      dateFilterInfo += ' (${_selectedSingleDate!.year}-${_selectedSingleDate!.month.toString().padLeft(2, '0')}-${_selectedSingleDate!.day.toString().padLeft(2, '0')})';
    } else if (_dateFilterType == '日期范围' && _selectedDateRange != null) {
      dateFilterInfo += ' (${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')} 至 ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')})';
    }
    rows.add([dateFilterInfo]);
    
    rows.add([]); // 空行
    // 修改表头为中文
    rows.add(['日期', '类型', '客户/供应商', '金额', '优惠', '付款方式', '备注']);

    for (var record in _records) {
      // 根据类型决定金额正负
      String amount = record['type'] == '进账' 
          ? '+${record['amount']}' 
          : '-${record['amount']}';
      
      rows.add([
        record['date'],
        record['type'],
        record['relatedName'],
        amount,
        record['discount'] > 0 ? record['discount'].toString() : '',
        record['paymentMethod'],
        record['note']
      ]);
    }

    // 添加总计行
    rows.add([]);
    rows.add(['总计', '', '', 
              '${_netAmount >= 0 ? '+' : ''}${_netAmount.toStringAsFixed(2)}', 
              _totalDiscountAmount > 0 ? _totalDiscountAmount.toStringAsFixed(2) : '', 
              '', '']);

    String csv = const ListToCsvConverter().convert(rows);

    if (Platform.isMacOS || Platform.isWindows) {
      // macOS 和 Windows: 使用 file_picker 让用户选择保存位置
      String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存员工业务记录',
        fileName: '${widget.employeeName}_records.csv',
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
        path = '${directory.path}/${widget.employeeName}_records.csv';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('存储权限被拒绝')),
        );
        return;
      }
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/${widget.employeeName}_records.csv';
    } else {
      // 其他平台使用应用文档目录作为后备方案
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/${widget.employeeName}_records.csv';
    }

    final file = File(path);
    await file.writeAsString(csv);

    if (Platform.isIOS) {
      // iOS 让用户手动选择存储位置
      await Share.shareFiles([file.path], text: '${widget.employeeName}的业务记录 CSV 文件');
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

  void _toggleIncomeFirst() {
    setState(() {
      _incomeFirst = !_incomeFirst;
      _fetchRecords();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.employeeName}的记录', style: TextStyle(
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
            icon: Icon(_incomeFirst ? Icons.swap_vert : Icons.swap_vert),
            tooltip: _incomeFirst ? '进账在前' : '汇款在前',
            onPressed: _toggleIncomeFirst,
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
          // 筛选条件 - 类型和日期在同一行
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.purple[50],
            child: Column(
              children: [
                // 第一行：类型筛选和日期类型筛选
                Row(
                  children: [
                    // 类型筛选
                    Icon(Icons.filter_alt, color: Colors.purple[700], size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonHideUnderline(
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple[300]!),
                            color: Colors.white,
                          ),
                          child: DropdownButton<String>(
                            hint: Text('选择类型', style: TextStyle(color: Colors.black87)),
                            value: _selectedType,
                            isExpanded: true,
                            icon: Icon(Icons.arrow_drop_down, color: Colors.purple[700]),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedType = newValue;
                                _fetchRecords();
                              });
                            },
                            style: TextStyle(color: Colors.black87, fontSize: 14),
                            items: [
                              DropdownMenuItem<String>(
                                value: '所有类型',
                                child: Text('所有类型'),
                              ),
                              DropdownMenuItem<String>(
                                value: '进账',
                                child: Text('进账'),
                              ),
                              DropdownMenuItem<String>(
                                value: '汇款',
                                child: Text('汇款'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    // 日期类型筛选
                    Icon(Icons.date_range, color: Colors.purple[700], size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonHideUnderline(
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple[300]!),
                            color: Colors.white,
                          ),
                          child: DropdownButton<String>(
                            hint: Text('日期筛选', style: TextStyle(color: Colors.black87)),
                            value: _dateFilterType,
                            isExpanded: true,
                            icon: Icon(Icons.arrow_drop_down, color: Colors.purple[700]),
                            onChanged: (String? newValue) {
                              setState(() {
                                _dateFilterType = newValue!;
                                if (_dateFilterType == '所有日期') {
                                  _selectedSingleDate = null;
                                  _selectedDateRange = null;
                                }
                                _fetchRecords();
                              });
                            },
                            style: TextStyle(color: Colors.black87, fontSize: 14),
                            items: [
                              DropdownMenuItem<String>(
                                value: '所有日期',
                                child: Text('所有日期'),
                              ),
                              DropdownMenuItem<String>(
                                value: '单日',
                                child: Text('单日'),
                              ),
                              DropdownMenuItem<String>(
                                value: '日期范围',
                                child: Text('日期范围'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                // 第二行：日期选择器（仅在需要时显示）
                if (_dateFilterType == '单日') ...[
                  SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedSingleDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(primary: Colors.purple),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedSingleDate = picked;
                          _fetchRecords();
                        });
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.purple[300]!),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.purple[700], size: 18),
                          SizedBox(width: 8),
                          Text(
                            _selectedSingleDate != null
                                ? '${_selectedSingleDate!.year}-${_selectedSingleDate!.month.toString().padLeft(2, '0')}-${_selectedSingleDate!.day.toString().padLeft(2, '0')}'
                                : '选择日期',
                            style: TextStyle(
                              color: _selectedSingleDate != null ? Colors.black87 : Colors.grey[600],
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.arrow_drop_down, color: Colors.purple[700]),
                        ],
                      ),
                    ),
                  ),
                ] else if (_dateFilterType == '日期范围') ...[
                  SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final initialDateRange = _selectedDateRange ??
                          DateTimeRange(
                            start: now.subtract(Duration(days: 30)),
                            end: now,
                          );
                      
                      final pickedRange = await showDateRangePicker(
                        context: context,
                        initialDateRange: initialDateRange,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(primary: Colors.purple),
                            ),
                            child: child!,
                          );
                        },
                      );
                      
                      if (pickedRange != null) {
                        setState(() {
                          _selectedDateRange = pickedRange;
                          _fetchRecords();
                        });
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.purple[300]!),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.date_range, color: Colors.purple[700], size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedDateRange != null
                                  ? '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')} 至 ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}'
                                  : '选择日期范围',
                              style: TextStyle(
                                color: _selectedDateRange != null ? Colors.black87 : Colors.grey[600],
                              ),
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: Colors.purple[700]),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 汇总信息卡片
          _buildSummaryCard(),

          Container(
            padding: EdgeInsets.all(12),
            color: Colors.purple[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.purple[700], size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '横向和纵向滑动可查看更多数据，进账以绿色显示，汇款以红色显示',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.purple[800],
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
                  backgroundColor: Colors.purple[100],
                  radius: 14,
                  child: Text(
                    widget.employeeName.isNotEmpty 
                        ? widget.employeeName[0].toUpperCase() 
                        : '?',
                    style: TextStyle(
                      color: Colors.purple[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '员工业务记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple[800],
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
                          '暂无业务记录',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _selectedType == '所有类型' 
                              ? '该员工还没有经办进账或汇款记录'
                              : '该员工还没有经办 $_selectedType 记录',
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
                            DataColumn(label: Text('客户/供应商')),
                            DataColumn(label: Text('金额')),
                            DataColumn(label: Text('优惠')),
                            DataColumn(label: Text('付款方式')),
                            DataColumn(label: Text('备注')),
                          ],
                          rows: [
                            // 数据行
                            ..._records.map((record) {
                              // 设置颜色，进账为绿色，汇款为红色
                              Color textColor = record['type'] == '进账' ? Colors.green : Colors.red;
                              
                              // 根据类型决定金额正负
                              String amount = record['type'] == '进账' 
                                  ? '+${record['amount']}' 
                                  : '-${record['amount']}';
                                  
                              return DataRow(
                                cells: [
                                  DataCell(Text(record['date'])),
                                  DataCell(
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: record['type'] == '进账' 
                                            ? Colors.green[50] 
                                            : Colors.red[50],
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: record['type'] == '进账' 
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
                                  DataCell(Text(record['relatedName'])),
                                  DataCell(
                                    Text(
                                      amount,
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  ),
                                  DataCell(
                                    record['discount'] > 0 
                                        ? Text(
                                            '¥${record['discount'].toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: Colors.orange[700],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          )
                                        : Text(''),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.grey[300]!),
                                      ),
                                      child: Text(
                                        record['paymentMethod'],
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[700],
                                        ),
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
                                  DataCell(Text('')), // 客户/供应商列
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
                                  DataCell(
                                    _totalDiscountAmount > 0
                                        ? Text(
                                            '¥${_totalDiscountAmount.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: Colors.orange[700],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          )
                                        : Text(''),
                                  ),
                                  DataCell(Text('')), // 付款方式列
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
      color: Colors.purple[50],
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 员工信息和汇总信息标题
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.badge, color: Colors.purple, size: 16),
                    SizedBox(width: 8),
                    Text(
                      '${widget.employeeName} - ${_selectedType ?? '所有类型'}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple[800],
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
                          color: Colors.purple[800],
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        _isSummaryExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 16,
                        color: Colors.purple[800],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isSummaryExpanded) ...[
              Divider(height: 16, thickness: 1),
              
              // 记录数和净收入
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('业务记录数', '${_records.length}', Colors.blue),
                  _buildSummaryItem('净收入', '${_netAmount >= 0 ? '+' : ''}¥${_netAmount.toStringAsFixed(2)}', _netAmount >= 0 ? Colors.green : Colors.red),
                ],
              ),
              SizedBox(height: 12),
              
              // 进账和汇款记录数
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('进账记录数', '${_incomeCount}', Colors.green),
                  _buildSummaryItem('汇款记录数', '${_remittanceCount}', Colors.red),
                ],
              ),
              SizedBox(height: 12),
              
              // 进账和汇款总额
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('进账总额', '+¥${_totalIncomeAmount.toStringAsFixed(2)}', Colors.green),
                  _buildSummaryItem('汇款总额', '-¥${_totalRemittanceAmount.toStringAsFixed(2)}', Colors.red),
                ],
              ),
              
              // 优惠金额（如果有的话）
              if (_totalDiscountAmount > 0) ...[
                SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSummaryItem('优惠总额', '¥${_totalDiscountAmount.toStringAsFixed(2)}', Colors.orange),
                  ],
                ),
              ],
              
              if (_incomeCount > 0 || _remittanceCount > 0) ...[
                Divider(height: 16, thickness: 1),
                
                // 平均金额
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSummaryItem('平均进账', _incomeCount > 0 ? '¥${(_totalIncomeAmount / _incomeCount).toStringAsFixed(2)}' : '¥0.00', Colors.green),
                    _buildSummaryItem('平均汇款', _remittanceCount > 0 ? '¥${(_totalRemittanceAmount / _remittanceCount).toStringAsFixed(2)}' : '¥0.00', Colors.red),
                  ],
                ),
              ],
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