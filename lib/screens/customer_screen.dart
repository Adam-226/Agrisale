// lib/screens/customer_screen.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import 'customer_records_screen.dart';
import 'customer_transactions_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerScreen extends StatefulWidget {
  @override
  _CustomerScreenState createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  List<Map<String, dynamic>> _customers = [];
  bool _showDeleteButtons = false; // 控制是否显示删除按钮

  // 添加搜索相关的状态变量
  List<Map<String, dynamic>> _filteredCustomers = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fetchCustomers();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterCustomers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 添加过滤客户的方法
  void _filterCustomers() {
    final searchText = _searchController.text.trim().toLowerCase();
    
    setState(() {
      if (searchText.isEmpty) {
        _filteredCustomers = List.from(_customers);
        _isSearching = false;
      } else {
        _filteredCustomers = _customers.where((customer) {
          final name = customer['name'].toString().toLowerCase();
          final note = (customer['note'] ?? '').toString().toLowerCase();
          return name.contains(searchText) || note.contains(searchText);
        }).toList();
        _isSearching = true;
      }
    });
  }

  Future<void> _fetchCustomers() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        // 只获取当前用户的客户
        final customers = await db.query('customers', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _customers = customers;
          _filteredCustomers = customers; // 初始时过滤列表等于全部列表
        });
      }
    }
  }

  Future<void> _addCustomer() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CustomerDialog(),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 检查当前用户下客户名称是否已存在
          final existingCustomer = await db.query(
            'customers',
            where: 'userId = ? AND name = ?',
            whereArgs: [userId, result['name']],
          );

          if (existingCustomer.isNotEmpty) {
            // 显示提示信息
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${result['name']} 已存在'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // 添加userId到客户数据
            result['userId'] = userId;
            await db.insert('customers', result);
            _fetchCustomers();
          }
        }
      }
    }
  }

  Future<void> _editCustomer(Map<String, dynamic> customer) async {
    // 确保传递给对话框的是一个副本，避免引用问题
    final Map<String, dynamic> customerCopy = Map<String, dynamic>.from(customer);
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CustomerDialog(customer: customerCopy),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 检查当前用户下客户名称是否已存在（排除当前编辑的客户）
          final existingCustomer = await db.query(
            'customers',
            where: 'userId = ? AND name = ? AND id != ?',
            whereArgs: [userId, result['name'], customer['id']],
          );

          if (existingCustomer.isNotEmpty) {
            // 显示提示信息
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${result['name']} 已存在'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // 确保userId不变
            result['userId'] = userId;
            await db.update(
              'customers', 
              result, 
              where: 'id = ? AND userId = ?', 
              whereArgs: [customer['id'], userId]
            );
            _fetchCustomers();
          }
        }
      }
    }
  }

  Future<void> _deleteCustomer(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('您确定要删除客户 "$name" 吗？'),
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
          // 只删除当前用户的客户
          await db.delete('customers', where: 'id = ? AND userId = ?', whereArgs: [id, userId]);
          // 更新当前用户的销售和退货记录，将删除的客户ID设为0
          await db.update(
            'sales',
            {'customerId': 0},
            where: 'customerId = ? AND userId = ?',
            whereArgs: [id, userId],
          );
          await db.update(
            'returns',
            {'customerId': 0},
            where: 'customerId = ? AND userId = ?',
            whereArgs: [id, userId],
          );
          _fetchCustomers();
        }
      }
    }
  }

  void _viewCustomerRecords(int customerId, String customerName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerRecordsScreen(customerId: customerId, customerName: customerName),
      ),
    );
  }

  void _viewCustomerTransactions(int customerId, String customerName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerTransactionsScreen(customerId: customerId, customerName: customerName),
      ),
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
          title: Text('客户', style: TextStyle(
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
        children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.people, color: Colors.orange[700], size: 20),
                  SizedBox(width: 8),
                  Text(
                    '客户列表',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[800],
                    ),
                  ),
                  Spacer(),
                  Text(
                    '共 ${_filteredCustomers.length} 位客户',
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
              child: _filteredCustomers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            _isSearching ? '没有匹配的客户' : '暂无客户',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加客户',
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
                      itemCount: _filteredCustomers.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                        final customer = _filteredCustomers[index];
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.orange[100],
                                    child: Text(
                                      customer['name'].toString().isNotEmpty 
                                          ? customer['name'].toString()[0].toUpperCase() 
                                          : '?',
                                      style: TextStyle(
                                        color: Colors.orange[800],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          customer['name'],
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if ((customer['note'] ?? '').toString().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              customer['note'],
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[600],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                                        icon: Icon(Icons.account_balance_wallet, color: Colors.purple),
                                        tooltip: '往来记录',
                                        onPressed: () => _viewCustomerTransactions(
                                          customer['id'] as int, 
                                          customer['name'] as String
                                        ),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                      ),
                                      SizedBox(width: 4),
                      IconButton(
                                        icon: Icon(Icons.list_alt, color: Colors.blue),
                                        tooltip: '查看记录',
                                        onPressed: () => _viewCustomerRecords(
                                          customer['id'] as int, 
                                          customer['name'] as String
                                        ),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                      ),
                                      SizedBox(width: 4),
                      IconButton(
                                        icon: Icon(Icons.edit, color: Colors.orange),
                                        tooltip: '编辑',
                        onPressed: () => _editCustomer(customer),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                                      ),
                                      if (_showDeleteButtons)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: IconButton(
                                          icon: Icon(Icons.delete, color: Colors.red),
                                          tooltip: '删除',
                                          onPressed: () => _deleteCustomer(
                                            customer['id'] as int, 
                                            customer['name'] as String
                                          ),
                                          constraints: BoxConstraints(),
                                          padding: EdgeInsets.all(8),
                                        ),
                      ),
                    ],
                                  ),
                                ],
                              ),
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
              child: Row(
                children: [
                  // 搜索框
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索客户...',
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
                          borderSide: BorderSide(color: Colors.orange),
                        ),
                      ),
                      // 添加键盘相关设置
                      textInputAction: TextInputAction.search,
                      onEditingComplete: () {
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                  SizedBox(width: 16),
                  // 添加按钮
                  FloatingActionButton(
        onPressed: _addCustomer,
        child: Icon(Icons.add),
                    tooltip: '添加客户',
                    backgroundColor: Colors.orange,
                    mini: false,
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

class CustomerDialog extends StatefulWidget {
  final Map<String, dynamic>? customer;

  CustomerDialog({this.customer});

  @override
  _CustomerDialogState createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<CustomerDialog> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.customer != null) {
      _nameController.text = widget.customer!['name'].toString();
      _noteController.text = (widget.customer!['note'] ?? '').toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.customer == null ? '添加客户' : '编辑客户',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      content: Form(
        key: _formKey,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            TextFormField(
            controller: _nameController,
              decoration: InputDecoration(
                labelText: '客户名称',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: Icon(Icons.person, color: Colors.orange),
          ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入客户名称';
                }
                return null;
              },
            ),
            SizedBox(height: 16),
            TextFormField(
            controller: _noteController,
              decoration: InputDecoration(
                labelText: '备注',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: Icon(Icons.note, color: Colors.orange),
              ),
              maxLines: 2,
          ),
        ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  final Map<String, dynamic> customer = {
                    'name': _nameController.text.trim(),
                    'note': _noteController.text.trim(),
                };
                  // 确保ID使用原始类型
                  if (widget.customer != null && widget.customer!.containsKey('id')) {
                    // 保留原始ID类型，不进行转换
                    customer['id'] = widget.customer!['id'];
                  }
                Navigator.of(context).pop(customer);
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

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }
}