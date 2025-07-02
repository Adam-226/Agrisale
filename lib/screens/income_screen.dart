// lib/screens/income_screen.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class IncomeScreen extends StatefulWidget {
  @override
  _IncomeScreenState createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  List<Map<String, dynamic>> _incomes = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _employees = [];
  bool _showDeleteButtons = false;

  // 添加搜索相关的状态变量
  List<Map<String, dynamic>> _filteredIncomes = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // 添加高级搜索相关变量
  bool _showAdvancedSearch = false;
  String? _selectedCustomerFilter;
  String? _selectedEmployeeFilter;
  String? _selectedPaymentMethodFilter;
  DateTimeRange? _selectedDateRange;
  final ValueNotifier<List<String>> _activeFilters = ValueNotifier<List<String>>([]);
  final List<String> _paymentMethods = ['现金', '微信转账', '银行卡'];

  @override
  void initState() {
    super.initState();
    _fetchData();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterIncomes();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _activeFilters.dispose();
    super.dispose();
  }

  // 重置所有过滤条件
  void _resetFilters() {
    setState(() {
      _selectedCustomerFilter = null;
      _selectedEmployeeFilter = null;
      _selectedPaymentMethodFilter = null;
      _selectedDateRange = null;
      _searchController.clear();
      _activeFilters.value = [];
      _filteredIncomes = List.from(_incomes);
      _isSearching = false;
      _showAdvancedSearch = false;
    });
  }

  // 更新搜索条件并显示活跃的过滤条件
  void _updateActiveFilters() {
    List<String> filters = [];
    
    if (_selectedCustomerFilter != null) {
      filters.add('客户: $_selectedCustomerFilter');
    }
    
    if (_selectedEmployeeFilter != null) {
      filters.add('员工: $_selectedEmployeeFilter');
    }
    
    if (_selectedPaymentMethodFilter != null) {
      filters.add('付款方式: $_selectedPaymentMethodFilter');
    }
    
    if (_selectedDateRange != null) {
      String startDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
      String endDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
      filters.add('日期: $startDate 至 $endDate');
    }
    
    _activeFilters.value = filters;
  }

  // 添加过滤进账记录的方法
  void _filterIncomes() {
    final searchText = _searchController.text.trim();
    final searchTerms = searchText.toLowerCase().split(' ').where((term) => term.isNotEmpty).toList();
    
    setState(() {
      // 开始筛选
      List<Map<String, dynamic>> result = List.from(_incomes);
      bool hasFilters = false;
      
      // 关键词搜索
      if (searchTerms.isNotEmpty) {
        hasFilters = true;
        result = result.where((income) {
          final customerName = (income['customerName'] ?? '').toString().toLowerCase();
          final employeeName = (income['employeeName'] ?? '').toString().toLowerCase();
          final date = income['incomeDate'].toString().toLowerCase();
          final note = (income['note'] ?? '').toString().toLowerCase();
          final amount = income['amount'].toString().toLowerCase();
          final discount = (income['discount'] ?? 0.0).toString().toLowerCase();
          final paymentMethod = income['paymentMethod'].toString().toLowerCase();
          
          // 检查所有搜索词是否都匹配
          return searchTerms.every((term) =>
            customerName.contains(term) ||
            employeeName.contains(term) ||
            date.contains(term) ||
            note.contains(term) ||
            amount.contains(term) ||
            discount.contains(term) ||
            paymentMethod.contains(term)
          );
        }).toList();
      }
      
      // 客户筛选
      if (_selectedCustomerFilter != null) {
        hasFilters = true;
        result = result.where((income) => 
          (income['customerName'] ?? '') == _selectedCustomerFilter).toList();
      }
      
      // 员工筛选
      if (_selectedEmployeeFilter != null) {
        hasFilters = true;
        result = result.where((income) => 
          (income['employeeName'] ?? '') == _selectedEmployeeFilter).toList();
      }
      
      // 付款方式筛选
      if (_selectedPaymentMethodFilter != null) {
        hasFilters = true;
        result = result.where((income) => 
          income['paymentMethod'] == _selectedPaymentMethodFilter).toList();
      }
      
      // 日期范围筛选
      if (_selectedDateRange != null) {
        hasFilters = true;
        result = result.where((income) {
          final incomeDate = DateTime.parse(income['incomeDate']);
          return incomeDate.isAfter(_selectedDateRange!.start.subtract(Duration(days: 1))) &&
                 incomeDate.isBefore(_selectedDateRange!.end.add(Duration(days: 1)));
        }).toList();
      }
      
      _isSearching = hasFilters;
      _filteredIncomes = result;
      _updateActiveFilters();
    });
  }

  Future<void> _fetchData() async {
    await _fetchCustomers();
    await _fetchEmployees(); 
    await _fetchIncomes();
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

  Future<void> _fetchEmployees() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final employees = await db.query('employees', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _employees = employees;
        });
      }
    }
  }

  Future<void> _fetchIncomes() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final incomes = await db.rawQuery('''
          SELECT i.*, c.name as customerName, e.name as employeeName
          FROM income i
          LEFT JOIN customers c ON i.customerId = c.id
          LEFT JOIN employees e ON i.employeeId = e.id
          WHERE i.userId = ?
          ORDER BY i.incomeDate DESC, i.id DESC
        ''', [userId]);
        setState(() {
          _incomes = incomes;
          _filteredIncomes = incomes; // 初始时过滤列表等于全部列表
        });
      }
    }
  }

  Future<void> _addIncome() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => IncomeDialog(
        customers: _customers,
        employees: _employees,
      ),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          result['userId'] = userId;
          await db.insert('income', result);
          _fetchIncomes();
        }
      }
    }
  }

  Future<void> _editIncome(Map<String, dynamic> income) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => IncomeDialog(
        income: income,
        customers: _customers,
        employees: _employees,
      ),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          result['userId'] = userId;
          await db.update(
            'income',
            result,
            where: 'id = ? AND userId = ?',
            whereArgs: [income['id'], userId],
          );
          _fetchIncomes();
        }
      }
    }
  }

  Future<void> _deleteIncome(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('您确定要删除这条进账记录吗？'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('确认'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('取消'),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          await db.delete('income', where: 'id = ? AND userId = ?', whereArgs: [id, userId]);
          _fetchIncomes();
        }
      }
    }
  }

  // 显示高级搜索对话框
  void _showAdvancedSearchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '高级搜索',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _resetFilters();
                          },
                          child: Text('重置所有'),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    
                    // 客户筛选
                    Text('按客户筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedCustomerFilter,
                        hint: Text('选择客户'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部客户'),
                          ),
                          ..._customers.map((customer) => DropdownMenuItem<String?>(
                            value: customer['name'],
                            child: Text(customer['name']),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedCustomerFilter = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // 员工筛选
                    Text('按员工筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedEmployeeFilter,
                        hint: Text('选择员工'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部员工'),
                          ),
                          ..._employees.map((employee) => DropdownMenuItem<String?>(
                            value: employee['name'],
                            child: Text(employee['name']),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedEmployeeFilter = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // 付款方式筛选
                    Text('按付款方式筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedPaymentMethodFilter,
                        hint: Text('选择付款方式'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部付款方式'),
                          ),
                          ..._paymentMethods.map((method) => DropdownMenuItem<String?>(
                            value: method,
                            child: Text(method),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedPaymentMethodFilter = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // 日期范围筛选
                    Text('按日期筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
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
                          lastDate: DateTime(2101),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.light(
                                  primary: Colors.teal,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        
                        if (pickedRange != null) {
                          setState(() {
                            _selectedDateRange = pickedRange;
                          });
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedDateRange != null
                                  ? '${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)} 至 ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}'
                                  : '选择日期范围',
                              style: TextStyle(
                                color: _selectedDateRange != null
                                    ? Colors.black
                                    : Colors.grey.shade600,
                              ),
                            ),
                            Icon(Icons.calendar_today, size: 18, color: Colors.grey.shade600),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    
                    // 确认按钮
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 20
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _filterIncomes();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            '应用筛选',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 添加手势检测器，点击空白处收起键盘
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('进账管理', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          IconButton(
            icon: Icon(_showDeleteButtons ? Icons.cancel : Icons.delete),
            tooltip: _showDeleteButtons ? '取消删除模式' : '开启删除模式',
            onPressed: () {
              setState(() {
                _showDeleteButtons = !_showDeleteButtons;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet, color: Colors.teal[700], size: 20),
                SizedBox(width: 8),
                Text(
                  '进账记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[800],
                  ),
                ),
                Spacer(),
                Text(
                  '共 ${_filteredIncomes.length} 条记录',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
          Expanded(
            child: _filteredIncomes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          _isSearching ? '没有匹配的进账记录' : '暂无进账记录',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _isSearching ? '请尝试其他搜索条件' : '点击右下角 + 按钮添加进账记录',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    // 让列表也能点击收起键盘
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _filteredIncomes.length,
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    itemBuilder: (context, index) {
                      final income = _filteredIncomes[index];
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
                                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                                      SizedBox(width: 4),
                                      Text(
                                        DateFormat('yyyy-MM-dd').format(DateTime.parse(income['incomeDate'])),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.edit, color: Colors.teal),
                                        tooltip: '编辑',
                                        onPressed: () => _editIncome(income),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                                      ),
                                      if (_showDeleteButtons)
                                        IconButton(
                                          icon: Icon(Icons.delete, color: Colors.red),
                                          tooltip: '删除',
                                          onPressed: () => _deleteIncome(income['id']),
                                          constraints: BoxConstraints(),
                                          padding: EdgeInsets.all(8),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '客户: ${income['customerName'] ?? '未指定'}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        '经办人: ${income['employeeName'] ?? '未指定'}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      // 显示实际进账金额
                                      Text(
                                        '¥${income['amount'].toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green[600],
                                        ),
                                      ),
                                      // 如果有优惠，显示优惠信息
                                      if ((income['discount'] ?? 0.0) > 0) ...[
                                        SizedBox(height: 2),
                                        Text(
                                          '原价: ¥${((income['amount'] ?? 0.0) + (income['discount'] ?? 0.0)).toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                            decoration: TextDecoration.lineThrough,
                                          ),
                                        ),
                                        Text(
                                          '优惠: ¥${(income['discount'] ?? 0.0).toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                      SizedBox(height: 4),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.teal[50],
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.teal[300]!),
                                        ),
                                        child: Text(
                                          income['paymentMethod'],
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.teal[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (income['note'] != null && income['note'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '备注: ${income['note']}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // 添加搜索栏和浮动按钮的容器
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // 活跃过滤条件显示
                ValueListenableBuilder<List<String>>(
                  valueListenable: _activeFilters,
                  builder: (context, filters, child) {
                    if (filters.isEmpty) return SizedBox.shrink();
                    
                    return Container(
                      margin: EdgeInsets.only(bottom: 8),
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.teal[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal[100]!)
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.filter_list, size: 16, color: Colors.teal),
                          SizedBox(width: 4),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: filters.map((filter) {
                                  return Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Chip(
                                      label: Text(filter, style: TextStyle(fontSize: 12)),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity(horizontal: -4, vertical: -4),
                                      backgroundColor: Colors.teal[100],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.clear, size: 16, color: Colors.teal),
                            onPressed: _resetFilters,
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Row(
                  children: [
                    // 搜索框
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '搜索进账记录...',
                          prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                          suffixIcon: _isSearching
                              ? IconButton(
                                  icon: Icon(Icons.clear, color: Colors.grey[600]),
                                  onPressed: () {
                                    _searchController.clear();
                                    FocusScope.of(context).unfocus();
                                  },
                                )
                              : null,
                          contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.teal),
                          ),
                        ),
                        // 添加键盘相关设置
                        textInputAction: TextInputAction.search,
                        onEditingComplete: () {
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    // 高级搜索按钮
                    IconButton(
                      onPressed: _showAdvancedSearchDialog,
                      icon: Icon(
                        Icons.tune,
                        color: _showAdvancedSearch ? Colors.teal : Colors.grey[600],
                        size: 20,
                      ),
                      tooltip: '高级搜索',
                    ),
                    SizedBox(width: 8),
                    // 添加按钮
                    FloatingActionButton(
                      onPressed: _addIncome,
                      child: Icon(Icons.add),
                      tooltip: '添加进账记录',
                      backgroundColor: Colors.teal,
                      mini: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
          FooterWidget(),
        ],
      ),
      ),
    );
  }
}

class IncomeDialog extends StatefulWidget {
  final Map<String, dynamic>? income;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> employees;

  IncomeDialog({
    this.income,
    required this.customers,
    required this.employees,
  });

  @override
  _IncomeDialogState createState() => _IncomeDialogState();
}

class _IncomeDialogState extends State<IncomeDialog> {
  final _amountController = TextEditingController();
  final _discountController = TextEditingController();
  final _originalPriceController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  DateTime _selectedDate = DateTime.now();
  int? _selectedCustomerId;
  int? _selectedEmployeeId;
  String _selectedPaymentMethod = '现金';
  bool _useOriginalPrice = false; // 是否使用优惠前价格计算模式
  
  final List<String> _paymentMethods = ['现金', '微信转账', '银行卡'];

  @override
  void initState() {
    super.initState();
    if (widget.income != null) {
      _selectedDate = DateTime.parse(widget.income!['incomeDate']);
      _selectedCustomerId = widget.income!['customerId'];
      _selectedEmployeeId = widget.income!['employeeId'];
      _selectedPaymentMethod = widget.income!['paymentMethod'];
      _amountController.text = widget.income!['amount'].toString();
      _discountController.text = (widget.income!['discount'] ?? 0.0).toString();
      _noteController.text = widget.income!['note'] ?? '';
      
      // 如果有优惠，计算优惠前价格
      final amount = widget.income!['amount'] as double;
      final discount = (widget.income!['discount'] ?? 0.0) as double;
      if (discount > 0) {
        _originalPriceController.text = (amount + discount).toString();
      }
    } else {
      _discountController.text = '0';
    }
    
    // 添加监听器来实现自动计算
    _amountController.addListener(_updateCalculations);
    _discountController.addListener(_updateCalculations);
    _originalPriceController.addListener(_updateCalculations);
  }

  @override
  void dispose() {
    _amountController.removeListener(_updateCalculations);
    _discountController.removeListener(_updateCalculations);
    _originalPriceController.removeListener(_updateCalculations);
    _amountController.dispose();
    _discountController.dispose();
    _originalPriceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _updateCalculations() {
    if (_useOriginalPrice) {
      // 从优惠前价格计算优惠
      final originalPrice = double.tryParse(_originalPriceController.text) ?? 0.0;
      final amount = double.tryParse(_amountController.text) ?? 0.0;
      final discount = originalPrice - amount;
      if (discount >= 0) {
        _discountController.text = discount.toString();
      }
    } else {
      // 从优惠金额计算优惠前价格
      final amount = double.tryParse(_amountController.text) ?? 0.0;
      final discount = double.tryParse(_discountController.text) ?? 0.0;
      final originalPrice = amount + discount;
      _originalPriceController.text = originalPrice.toString();
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.income == null ? '添加进账记录' : '编辑进账记录',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 日期选择
              InkWell(
                onTap: _selectDate,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[50],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, color: Colors.teal),
                      SizedBox(width: 12),
                      Text(
                        DateFormat('yyyy-MM-dd').format(_selectedDate),
                        style: TextStyle(fontSize: 16),
                      ),
                      Spacer(),
                      Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
              
              // 客户选择
              DropdownButtonFormField<int>(
                value: _selectedCustomerId,
                decoration: InputDecoration(
                  labelText: '客户',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.person, color: Colors.teal),
                ),
                items: [
                  DropdownMenuItem<int>(
                    value: null,
                    child: Text('未选择客户'),
                  ),
                  ...widget.customers.map<DropdownMenuItem<int>>((customer) {
                    return DropdownMenuItem<int>(
                      value: customer['id'],
                      child: Text(customer['name']),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedCustomerId = value;
                  });
                },
              ),
              SizedBox(height: 16),
              
              // 计算方式选择
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[50],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        title: Text('直接输入优惠', style: TextStyle(fontSize: 14)),
                        value: false,
                        groupValue: _useOriginalPrice,
                        onChanged: (value) {
                          setState(() {
                            _useOriginalPrice = value!;
                            _updateCalculations();
                          });
                        },
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        title: Text('优惠前价格', style: TextStyle(fontSize: 14)),
                        value: true,
                        groupValue: _useOriginalPrice,
                        onChanged: (value) {
                          setState(() {
                            _useOriginalPrice = value!;
                            _updateCalculations();
                          });
                        },
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              
              // 实际进账金额
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: '实际进账金额',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.attach_money, color: Colors.teal),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入实际进账金额';
                  }
                  if (double.tryParse(value) == null) {
                    return '请输入有效的金额';
                  }
                  if (double.parse(value) <= 0) {
                    return '金额必须大于0';
                  }
                  return null;
                },
                onChanged: (value) => _updateCalculations(),
              ),
              SizedBox(height: 16),
              
              // 优惠相关输入
              if (_useOriginalPrice) ...[
                // 优惠前价格输入
                TextFormField(
                  controller: _originalPriceController,
                  decoration: InputDecoration(
                    labelText: '优惠前价格',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    prefixIcon: Icon(Icons.local_offer, color: Colors.orange),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) => _updateCalculations(),
                ),
                SizedBox(height: 16),
                
                // 显示计算出的优惠金额
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('计算出的优惠金额:', style: TextStyle(fontWeight: FontWeight.w500)),
                      Text(
                        '¥${_discountController.text}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // 直接输入优惠金额
                TextFormField(
                  controller: _discountController,
                  decoration: InputDecoration(
                    labelText: '优惠金额',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    prefixIcon: Icon(Icons.discount, color: Colors.orange),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final discount = double.tryParse(value);
                      if (discount == null) {
                        return '请输入有效的优惠金额';
                      }
                      if (discount < 0) {
                        return '优惠金额不能为负数';
                      }
                    }
                    return null;
                  },
                  onChanged: (value) => _updateCalculations(),
                ),
                SizedBox(height: 16),
                
                // 显示计算出的优惠前价格
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('优惠前价格:', style: TextStyle(fontWeight: FontWeight.w500)),
                      Text(
                        '¥${_originalPriceController.text}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 16),
              
              // 员工选择
              DropdownButtonFormField<int>(
                value: _selectedEmployeeId,
                decoration: InputDecoration(
                  labelText: '经办人',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.badge, color: Colors.teal),
                ),
                items: [
                  DropdownMenuItem<int>(
                    value: null,
                    child: Text('未选择经办人'),
                  ),
                  ...widget.employees.map<DropdownMenuItem<int>>((employee) {
                    return DropdownMenuItem<int>(
                      value: employee['id'],
                      child: Text(employee['name']),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedEmployeeId = value;
                  });
                },
              ),
              SizedBox(height: 16),
              
              // 付款方式选择
              DropdownButtonFormField<String>(
                value: _selectedPaymentMethod,
                decoration: InputDecoration(
                  labelText: '付款方式',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.payment, color: Colors.teal),
                ),
                items: _paymentMethods.map<DropdownMenuItem<String>>((method) {
                  return DropdownMenuItem<String>(
                    value: method,
                    child: Text(method),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedPaymentMethod = value!;
                  });
                },
              ),
              SizedBox(height: 16),
              
              // 备注
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.note, color: Colors.teal),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  final Map<String, dynamic> income = {
                    'incomeDate': _selectedDate.toIso8601String().split('T')[0],
                    'customerId': _selectedCustomerId,
                    'amount': double.parse(_amountController.text.trim()),
                    'discount': double.tryParse(_discountController.text.trim()) ?? 0.0,
                    'employeeId': _selectedEmployeeId,
                    'paymentMethod': _selectedPaymentMethod,
                    'note': _noteController.text.trim(),
                  };
                  if (widget.income != null) {
                    income['id'] = widget.income!['id'];
                  }
                  Navigator.of(context).pop(income);
                }
              },
              child: Text('保存'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('取消'),
            ),
          ],
        ),
      ],
    );
  }
}
 