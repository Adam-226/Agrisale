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

class PurchaseRemittanceAnalysisScreen extends StatefulWidget {
  @override
  _PurchaseRemittanceAnalysisScreenState createState() => _PurchaseRemittanceAnalysisScreenState();
}

class _PurchaseRemittanceAnalysisScreenState extends State<PurchaseRemittanceAnalysisScreen> {
  List<Map<String, dynamic>> _analysisData = [];
  bool _isLoading = false;
  bool _isDescending = true;
  String _sortColumn = 'date';
  
  // 筛选条件
  DateTimeRange? _selectedDateRange;
  String? _selectedSupplier;
  List<Map<String, dynamic>> _suppliers = [];
  
  // 汇总数据
  double _totalPurchases = 0.0;
  double _totalRemittances = 0.0;
  double _totalDifference = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchSuppliers();
    _fetchAnalysisData();
  }

  Future<void> _fetchSuppliers() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _suppliers = suppliers;
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
          // 构建日期和供应商筛选条件
          String dateFilter = '';
          String supplierFilter = '';
          List<dynamic> params = [userId];
          
          if (_selectedDateRange != null) {
            dateFilter = 'AND DATE(p.purchaseDate) >= ? AND DATE(p.purchaseDate) <= ?';
            params.add(_selectedDateRange!.start.toIso8601String().split('T')[0]);
            params.add(_selectedDateRange!.end.toIso8601String().split('T')[0]);
          }
          
          if (_selectedSupplier != null && _selectedSupplier != '所有供应商') {
            supplierFilter = 'AND s.name = ?';
            params.add(_selectedSupplier!);
          }

          // 查询采购数据（按日期和供应商分组）
          final purchasesQuery = '''
            SELECT 
              DATE(p.purchaseDate) as date,
              s.name as supplierName,
              s.id as supplierId,
              SUM(p.totalPurchasePrice) as totalPurchases
            FROM purchases p
            LEFT JOIN suppliers s ON p.supplierId = s.id
            WHERE p.userId = ? $dateFilter $supplierFilter
            GROUP BY DATE(p.purchaseDate), p.supplierId
          ''';
          
          final purchasesData = await db.rawQuery(purchasesQuery, params);

          // 查询汇款数据（按日期和供应商分组）
          final remittanceQuery = '''
            SELECT 
              DATE(r.remittanceDate) as date,
              s.name as supplierName,
              s.id as supplierId,
              SUM(r.amount) as totalRemittances
            FROM remittance r
            LEFT JOIN suppliers s ON r.supplierId = s.id
            WHERE r.userId = ? $dateFilter $supplierFilter
            GROUP BY DATE(r.remittanceDate), r.supplierId
          ''';
          
          final remittanceData = await db.rawQuery(remittanceQuery, params);

          // 合并数据
          Map<String, Map<String, dynamic>> combinedData = {};
          
          // 处理采购数据
          for (var purchase in purchasesData) {
            String key = '${purchase['date']}_${purchase['supplierId'] ?? 'null'}';
            combinedData[key] = {
              'date': purchase['date'],
              'supplierName': purchase['supplierName'] ?? '未指定供应商',
              'supplierId': purchase['supplierId'],
              'totalPurchases': (purchase['totalPurchases'] as num?)?.toDouble() ?? 0.0,
              'totalRemittances': 0.0,
            };
          }
          
          // 处理汇款数据
          for (var remittance in remittanceData) {
            String key = '${remittance['date']}_${remittance['supplierId'] ?? 'null'}';
            if (combinedData.containsKey(key)) {
              combinedData[key]!['totalRemittances'] = (remittance['totalRemittances'] as num?)?.toDouble() ?? 0.0;
            } else {
              combinedData[key] = {
                'date': remittance['date'],
                'supplierName': remittance['supplierName'] ?? '未指定供应商',
                'supplierId': remittance['supplierId'],
                'totalPurchases': 0.0,
                'totalRemittances': (remittance['totalRemittances'] as num?)?.toDouble() ?? 0.0,
              };
            }
          }

          // 计算差异
          List<Map<String, dynamic>> analysisData = [];
          for (var data in combinedData.values) {
            double totalPurchases = data['totalPurchases'];
            double totalRemittances = data['totalRemittances'];
            double difference = totalPurchases - totalRemittances;
            
            analysisData.add({
              'date': data['date'],
              'supplierName': data['supplierName'],
              'supplierId': data['supplierId'],
              'totalPurchases': totalPurchases,
              'totalRemittances': totalRemittances,
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
      print('采购汇款分析数据加载错误: $e');
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
    double totalPurchases = 0.0;
    double totalRemittances = 0.0;
    double totalDifference = 0.0;

    for (var item in data) {
      totalPurchases += item['totalPurchases'];
      totalRemittances += item['totalRemittances'];
      totalDifference += item['difference'];
    }

    setState(() {
      _totalPurchases = totalPurchases;
      _totalRemittances = totalRemittances;
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
    rows.add(['采购-汇款明细分析 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    
    // 添加筛选条件
    String supplierFilter = _selectedSupplier ?? '所有供应商';
    rows.add(['供应商筛选: $supplierFilter']);
    
    String dateFilter = '所有日期';
    if (_selectedDateRange != null) {
      dateFilter = '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')} 至 ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}';
    }
    rows.add(['日期范围: $dateFilter']);
    rows.add([]);
    
    // 表头
    rows.add(['日期', '供应商', '净采购额', '实际汇款', '差异']);

    // 数据行
    for (var item in _analysisData) {
      rows.add([
        item['date'],
        item['supplierName'],
        item['totalPurchases'].toStringAsFixed(2),
        item['totalRemittances'].toStringAsFixed(2),
        item['difference'].toStringAsFixed(2),
      ]);
    }

    // 总计行
    rows.add([]);
    rows.add([
      '总计', '',
      _totalPurchases.toStringAsFixed(2), // 净采购额
      _totalRemittances.toStringAsFixed(2),
      _totalDifference.toStringAsFixed(2),
    ]);

    String csv = const ListToCsvConverter().convert(rows);

    if (Platform.isMacOS || Platform.isWindows) {
      String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存采购汇款分析报告',
        fileName: 'purchase_remittance_analysis.csv',
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
        path = '${directory.path}/purchase_remittance_analysis.csv';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('存储权限被拒绝')),
        );
        return;
      }
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/purchase_remittance_analysis.csv';
    } else {
      final directory = await getApplicationDocumentsDirectory();
      path = '${directory.path}/purchase_remittance_analysis.csv';
    }

    final file = File(path);
    await file.writeAsString(csv);

    if (Platform.isIOS) {
      await Share.shareFiles([file.path], text: '采购汇款分析报告 CSV 文件');
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
        title: Text('采购-汇款明细', style: TextStyle(
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
                    '分析每日每供应商的采购（含退货）与汇款对应情况，差异为正表示欠款，为负表示超付',
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
              // 供应商筛选
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('供应商筛选', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          hint: Text('选择供应商'),
                          value: _selectedSupplier,
                          isExpanded: true,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedSupplier = newValue;
                              _fetchAnalysisData();
                            });
                          },
                          items: [
                            DropdownMenuItem<String>(
                              value: '所有供应商',
                              child: Text('所有供应商'),
                            ),
                            ..._suppliers.map((supplier) {
                              return DropdownMenuItem<String>(
                                value: supplier['name'],
                                child: Text(supplier['name']),
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
          if (_selectedDateRange != null || _selectedSupplier != null) ...[
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
                if (_selectedSupplier != null && _selectedSupplier != '所有供应商')
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedSupplier = null;
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
                          Text('供应商: $_selectedSupplier', style: TextStyle(fontSize: 12)),
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
                _buildSummaryItem('净采购额', '¥${_totalPurchases.toStringAsFixed(2)}', Colors.blue),
                _buildSummaryItem('实际汇款', '¥${_totalRemittances.toStringAsFixed(2)}', Colors.orange),
                _buildSummaryItem('差异', '¥${_totalDifference.toStringAsFixed(2)}', _totalDifference >= 0 ? Colors.red : Colors.green),
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
              label: Text('供应商'),
              onSort: (columnIndex, ascending) => _onSort('supplierName'),
            ),
            DataColumn(
              label: Text('净采购额'),
              numeric: true,
              onSort: (columnIndex, ascending) => _onSort('totalPurchases'),
            ),
            DataColumn(
              label: Text('实际汇款'),
              numeric: true,
              onSort: (columnIndex, ascending) => _onSort('totalRemittances'),
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
                  DataCell(Text(item['supplierName'] ?? '')),
                  DataCell(Text('¥${item['totalPurchases'].toStringAsFixed(2)}', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                  DataCell(Text('¥${item['totalRemittances'].toStringAsFixed(2)}', 
                    style: TextStyle(color: Colors.orange))),
                  DataCell(Text('¥${item['difference'].toStringAsFixed(2)}', 
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: item['difference'] >= 0 ? Colors.red : Colors.green
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
                  DataCell(Text('¥${_totalPurchases.toStringAsFixed(2)}', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                  DataCell(Text('¥${_totalRemittances.toStringAsFixed(2)}', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
                  DataCell(Text('¥${_totalDifference.toStringAsFixed(2)}', 
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _totalDifference >= 0 ? Colors.red : Colors.green
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
      case 'supplierName': return 1;
      case 'totalPurchases': return 2;
      case 'totalRemittances': return 3;
      case 'difference': return 4;
      default: return 0;
    }
  }
} 