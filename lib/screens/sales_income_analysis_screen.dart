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

class SalesIncomeAnalysisScreen extends StatefulWidget {
  @override
  _SalesIncomeAnalysisScreenState createState() => _SalesIncomeAnalysisScreenState();
}

class _SalesIncomeAnalysisScreenState extends State<SalesIncomeAnalysisScreen> {
  List<Map<String, dynamic>> _analysisData = [];
  bool _isLoading = false;
  bool _isDescending = true;
  String _sortColumn = 'date';
  
  // 筛选条件
  DateTimeRange? _selectedDateRange;
  String? _selectedCustomer;
  List<Map<String, dynamic>> _customers = [];
  
  // 汇总数据
  double _totalNetSales = 0.0;
  double _totalActualPayment = 0.0;
  double _totalDiscount = 0.0;
  double _totalDifference = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchCustomers();
    _fetchAnalysisData();
  }

  Future<void> _fetchCustomers() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final customers = await db.query('customers', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _customers = customers;
        });
      }
    }
  }

  Future<void> _fetchAnalysisData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 构建日期和客户筛选条件
          String dateFilter = '';
          String customerFilter = '';
          List<dynamic> params = [userId];
          
          if (_selectedDateRange != null) {
            dateFilter = 'AND DATE(s.saleDate) >= ? AND DATE(s.saleDate) <= ?';
            params.add(_selectedDateRange!.start.toIso8601String().split('T')[0]);
            params.add(_selectedDateRange!.end.toIso8601String().split('T')[0]);
          }
          
          if (_selectedCustomer != null && _selectedCustomer != '所有客户') {
            customerFilter = 'AND c.name = ?';
            params.add(_selectedCustomer!);
          }

          // 查询销售数据（按日期和客户分组）
          final salesQuery = '''
            SELECT 
              DATE(s.saleDate) as date,
              c.name as customerName,
              c.id as customerId,
              SUM(s.totalSalePrice) as totalSales
            FROM sales s
            LEFT JOIN customers c ON s.customerId = c.id
            WHERE s.userId = ? $dateFilter $customerFilter
            GROUP BY DATE(s.saleDate), s.customerId
          ''';
          
          final salesData = await db.rawQuery(salesQuery, params);

          // 查询退货数据（按日期和客户分组）
          final returnsQuery = '''
            SELECT 
              DATE(r.returnDate) as date,
              c.name as customerName,
              c.id as customerId,
              SUM(r.totalReturnPrice) as totalReturns
            FROM returns r
            LEFT JOIN customers c ON r.customerId = c.id
            WHERE r.userId = ? $dateFilter $customerFilter
            GROUP BY DATE(r.returnDate), r.customerId
          ''';
          
          final returnsData = await db.rawQuery(returnsQuery, params);

          // 查询进账数据（按日期和客户分组）
          final incomeQuery = '''
            SELECT 
              DATE(i.incomeDate) as date,
              c.name as customerName,
              c.id as customerId,
              SUM(i.amount) as totalPayment,
              SUM(i.discount) as totalDiscount
            FROM income i
            LEFT JOIN customers c ON i.customerId = c.id
            WHERE i.userId = ? $dateFilter $customerFilter
            GROUP BY DATE(i.incomeDate), i.customerId
          ''';
          
          final incomeData = await db.rawQuery(incomeQuery, params);

          // 合并数据
          Map<String, Map<String, dynamic>> combinedData = {};
          
          // 处理销售数据
          for (var sale in salesData) {
            String key = '${sale['date']}_${sale['customerId'] ?? 'null'}';
            combinedData[key] = {
              'date': sale['date'],
              'customerName': sale['customerName'] ?? '未指定客户',
              'customerId': sale['customerId'],
              'totalSales': (sale['totalSales'] as num?)?.toDouble() ?? 0.0,
              'totalReturns': 0.0,
              'totalPayment': 0.0,
              'totalDiscount': 0.0,
            };
          }
          
          // 处理退货数据
          for (var returnItem in returnsData) {
            String key = '${returnItem['date']}_${returnItem['customerId'] ?? 'null'}';
            if (combinedData.containsKey(key)) {
              combinedData[key]!['totalReturns'] = (returnItem['totalReturns'] as num?)?.toDouble() ?? 0.0;
            } else {
              combinedData[key] = {
                'date': returnItem['date'],
                'customerName': returnItem['customerName'] ?? '未指定客户',
                'customerId': returnItem['customerId'],
                'totalSales': 0.0,
                'totalReturns': (returnItem['totalReturns'] as num?)?.toDouble() ?? 0.0,
                'totalPayment': 0.0,
                'totalDiscount': 0.0,
              };
            }
          }
          
          // 处理进账数据
          for (var income in incomeData) {
            String key = '${income['date']}_${income['customerId'] ?? 'null'}';
            if (combinedData.containsKey(key)) {
              combinedData[key]!['totalPayment'] = (income['totalPayment'] as num?)?.toDouble() ?? 0.0;
              combinedData[key]!['totalDiscount'] = (income['totalDiscount'] as num?)?.toDouble() ?? 0.0;
            } else {
              combinedData[key] = {
                'date': income['date'],
                'customerName': income['customerName'] ?? '未指定客户',
                'customerId': income['customerId'],
                'totalSales': 0.0,
                'totalReturns': 0.0,
                'totalPayment': (income['totalPayment'] as num?)?.toDouble() ?? 0.0,
                'totalDiscount': (income['totalDiscount'] as num?)?.toDouble() ?? 0.0,
              };
            }
          }

          // 计算净销售额、理论应付、实际应付和差异
          List<Map<String, dynamic>> analysisData = [];
          for (var data in combinedData.values) {
            double netSales = data['totalSales'] - data['totalReturns'];
            double actualPayment = data['totalPayment'];
            double discount = data['totalDiscount'];
            double theoreticalPayable = netSales;
            double actualPayable = actualPayment + discount;
            double difference = theoreticalPayable - actualPayable;
            
            analysisData.add({
              'date': data['date'],
              'customerName': data['customerName'],
              'customerId': data['customerId'],
              'totalSales': data['totalSales'],
              'totalReturns': data['totalReturns'],
              'netSales': netSales,
              'actualPayment': actualPayment,
              'discount': discount,
              'theoreticalPayable': theoreticalPayable,
              'actualPayable': actualPayable,
              'difference': difference,
            });
          }

          // 排序
          _sortData(analysisData);
          
          // 计算汇总
          _calculateSummary(analysisData);

          setState(() {
            _analysisData = analysisData;
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('无法获取用户信息')),
            );
          }
        }
      } else {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('用户未登录')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('数据加载失败: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      print('销售进账分析数据加载错误: $e');
    }
  }

  void _sortData(List<Map<String, dynamic>> data) {
    data.sort((a, b) {
      dynamic aValue = a[_sortColumn];
      dynamic bValue = b[_sortColumn];
      
      if (aValue == null && bValue == null) return 0;
      if (aValue == null) return _isDescending ? 1 : -1;
      if (bValue == null) return _isDescending ? -1 : 1;
      
      int comparison;
      if (aValue is String && bValue is String) {
        comparison = aValue.compareTo(bValue);
      } else if (aValue is num && bValue is num) {
        comparison = aValue.compareTo(bValue);
      } else {
        comparison = aValue.toString().compareTo(bValue.toString());
      }
      
      return _isDescending ? -comparison : comparison;
    });
  }

  void _calculateSummary(List<Map<String, dynamic>> data) {
    double totalNetSales = 0.0;
    double totalActualPayment = 0.0;
    double totalDiscount = 0.0;
    double totalDifference = 0.0;

    for (var item in data) {
      totalNetSales += item['netSales'];
      totalActualPayment += item['actualPayment'];
      totalDiscount += item['discount'];
      totalDifference += item['difference'];
    }

    setState(() {
      _totalNetSales = totalNetSales;
      _totalActualPayment = totalActualPayment;
      _totalDiscount = totalDiscount;
      _totalDifference = totalDifference;
    });
  }

  void _onSort(String columnName) {
    setState(() {
      if (_sortColumn == columnName) {
        _isDescending = !_isDescending;
      } else {
        _sortColumn = columnName;
        _isDescending = true;
      }
      _sortData(_analysisData);
    });
  }

  Future<void> _exportToCSV() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    List<List<dynamic>> rows = [];
    rows.add(['总销售-进账明细分析 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    
    // 添加筛选条件
    String customerFilter = _selectedCustomer ?? '所有客户';
    rows.add(['客户筛选: $customerFilter']);
    
    String dateFilter = '所有日期';
    if (_selectedDateRange != null) {
      dateFilter = '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')} 至 ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}';
    }
    rows.add(['日期范围: $dateFilter']);
    rows.add([]);
    
    // 表头
    rows.add(['日期', '客户', '销售总额', '退货总额', '净销售额', '应收', '优惠金额', '实际收款', '差异']);

    // 数据行
    for (var item in _analysisData) {
      rows.add([
        item['date'],
        item['customerName'],
        item['totalSales'].toStringAsFixed(2),
        item['totalReturns'].toStringAsFixed(2),
        item['netSales'].toStringAsFixed(2),
        item['actualPayable'].toStringAsFixed(2),
        item['discount'].toStringAsFixed(2),
        item['actualPayment'].toStringAsFixed(2),
        item['difference'].toStringAsFixed(2),
      ]);
    }

    // 总计行
    rows.add([]);
    rows.add([
      '总计', '', '', '',
      _totalNetSales.toStringAsFixed(2),
      (_totalActualPayment + _totalDiscount).toStringAsFixed(2), // 应收
      _totalDiscount.toStringAsFixed(2),
      _totalActualPayment.toStringAsFixed(2), // 实际收款
      _totalDifference.toStringAsFixed(2),
    ]);

    String csv = const ListToCsvConverter().convert(rows);

    if (Platform.isMacOS || Platform.isWindows) {
      String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存销售进账分析报告',
        fileName: 'sales_income_analysis.csv',
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
      if (await Permission.storage.request().isGranted) {
        final directory = Directory('/storage/emulated/0/Download');
        path = '${directory.path}/sales_income_analysis.csv';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('存储权限被拒绝')),
        );
        return;
      }
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/sales_income_analysis.csv';
    } else {
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/sales_income_analysis.csv';
    }

    final file = File(path);
    await file.writeAsString(csv);

    if (Platform.isIOS) {
      await Share.shareFiles([file.path], text: '销售进账分析报告 CSV 文件');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出成功: $path')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('总销售-进账明细', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _fetchAnalysisData,
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
          // 筛选条件
          _buildFilterSection(),
          
          // 汇总信息卡片
          _buildSummaryCard(),
          
          // 提示信息
          Container(
            padding: EdgeInsets.all(12),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '分析每日每客户的销售与收款对应情况，差异为正表示欠款，为负表示超收',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 数据表格
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _analysisData.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.analytics, size: 64, color: Colors.grey[400]),
                            SizedBox(height: 16),
                            Text(
                              '暂无分析数据',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : _buildDataTable(),
          ),
          
          FooterWidget(),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        children: [
          Row(
            children: [
              // 客户筛选
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('客户筛选', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    DropdownButtonHideUnderline(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: DropdownButton<String>(
                          hint: Text('选择客户'),
                          value: _selectedCustomer,
                          isExpanded: true,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedCustomer = newValue;
                              _fetchAnalysisData();
                            });
                          },
                          items: [
                            DropdownMenuItem<String>(
                              value: '所有客户',
                              child: Text('所有客户'),
                            ),
                            ..._customers.map((customer) {
                              return DropdownMenuItem<String>(
                                value: customer['name'],
                                child: Text(customer['name']),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 16),
              // 日期范围筛选
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('日期范围', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
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
                        );
                        
                        if (pickedRange != null) {
                          setState(() {
                            _selectedDateRange = pickedRange;
                            _fetchAnalysisData();
                          });
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.date_range, size: 18),
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
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_selectedDateRange != null || _selectedCustomer != null) ...[
            SizedBox(height: 12),
            Row(
              children: [
                Text('清除筛选: ', style: TextStyle(color: Colors.grey[600])),
                if (_selectedDateRange != null)
                  Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDateRange = null;
                          _fetchAnalysisData();
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('日期范围', style: TextStyle(fontSize: 12)),
                            SizedBox(width: 4),
                            Icon(Icons.close, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_selectedCustomer != null && _selectedCustomer != '所有客户')
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCustomer = null;
                        _fetchAnalysisData();
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                                              child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('客户: $_selectedCustomer', style: TextStyle(fontSize: 12)),
                            SizedBox(width: 4),
                            Icon(Icons.close, size: 14),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      margin: EdgeInsets.all(8),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '汇总统计',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSummaryItem('净销售额', '¥${_totalNetSales.toStringAsFixed(2)}', Colors.blue),
                _buildSummaryItem('实际收款', '¥${_totalActualPayment.toStringAsFixed(2)}', Colors.green),
                _buildSummaryItem('优惠总额', '¥${_totalDiscount.toStringAsFixed(2)}', Colors.orange),
                _buildSummaryItem('差异', '¥${_totalDifference.toStringAsFixed(2)}', _totalDifference >= 0 ? Colors.red : Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 4),
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

  Widget _buildDataTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: _getSortColumnIndex(),
          sortAscending: !_isDescending,
          horizontalMargin: 12,
          columnSpacing: 16,
          headingTextStyle: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blue[800],
            fontSize: 12,
          ),
          dataTextStyle: TextStyle(fontSize: 11),
          columns: [
            DataColumn(
              label: Text('日期'),
              onSort: (columnIndex, ascending) => _onSort('date'),
            ),
            DataColumn(
              label: Text('客户'),
              onSort: (columnIndex, ascending) => _onSort('customerName'),
            ),
            DataColumn(
              label: Text('销售总额'),
              numeric: true,
              onSort: (columnIndex, ascending) => _onSort('totalSales'),
            ),
            DataColumn(
              label: Text('退货总额'),
              numeric: true,
              onSort: (columnIndex, ascending) => _onSort('totalReturns'),
            ),
            DataColumn(
              label: Text('净销售额'),
              numeric: true,
              onSort: (columnIndex, ascending) => _onSort('netSales'),
            ),
            DataColumn(
              label: Text('应收'),
              numeric: true,
              onSort: (columnIndex, ascending) => _onSort('actualPayable'),
            ),
            DataColumn(
              label: Text('优惠金额'),
              numeric: true,
              onSort: (columnIndex, ascending) => _onSort('discount'),
            ),
            DataColumn(
              label: Text('实际收款'),
              numeric: true,
              onSort: (columnIndex, ascending) => _onSort('actualPayment'),
            ),
            DataColumn(
              label: Text('差异'),
              numeric: true,
              onSort: (columnIndex, ascending) => _onSort('difference'),
            ),
          ],
          rows: [
            ..._analysisData.map((item) {
              return DataRow(
                cells: [
                  DataCell(Text(item['date'] ?? '')),
                  DataCell(Text(item['customerName'] ?? '')),
                  DataCell(Text('¥${item['totalSales'].toStringAsFixed(2)}')),
                  DataCell(Text('¥${item['totalReturns'].toStringAsFixed(2)}')),
                  DataCell(Text('¥${item['netSales'].toStringAsFixed(2)}', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                  DataCell(Text('¥${item['actualPayable'].toStringAsFixed(2)}')),
                  DataCell(item['discount'] > 0 
                    ? Text('¥${item['discount'].toStringAsFixed(2)}', 
                        style: TextStyle(color: Colors.orange))
                    : Text('')),
                  DataCell(Text('¥${item['actualPayment'].toStringAsFixed(2)}', 
                    style: TextStyle(color: Colors.green))),
                  DataCell(Text('¥${item['difference'].toStringAsFixed(2)}', 
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: item['difference'] >= 0 ? Colors.red : Colors.purple
                    ))),
                ],
              );
            }).toList(),
            
            // 总计行
            if (_analysisData.isNotEmpty)
              DataRow(
                color: MaterialStateProperty.all(Colors.grey[100]),
                cells: [
                  DataCell(Text('总计', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text('')),
                  DataCell(Text('')),
                  DataCell(Text('')),
                  DataCell(Text('¥${_totalNetSales.toStringAsFixed(2)}', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                  DataCell(Text('¥${(_totalActualPayment + _totalDiscount).toStringAsFixed(2)}', 
                    style: TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text('¥${_totalDiscount.toStringAsFixed(2)}', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
                  DataCell(Text('¥${_totalActualPayment.toStringAsFixed(2)}', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                  DataCell(Text('¥${_totalDifference.toStringAsFixed(2)}', 
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _totalDifference >= 0 ? Colors.red : Colors.purple
                    ))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  int _getSortColumnIndex() {
    switch (_sortColumn) {
      case 'date': return 0;
      case 'customerName': return 1;
      case 'totalSales': return 2;
      case 'totalReturns': return 3;
      case 'netSales': return 4;
      case 'actualPayable': return 5;
      case 'discount': return 6;
      case 'actualPayment': return 7;
      case 'difference': return 8;
      default: return 0;
    }
  }
}
 