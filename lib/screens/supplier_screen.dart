// lib/screens/supplier_screen.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import 'supplier_records_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SupplierScreen extends StatefulWidget {
  @override
  _SupplierScreenState createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  List<Map<String, dynamic>> _suppliers = [];
  bool _showDeleteButtons = false; // 控制是否显示删除按钮

  // 添加搜索相关的状态变量
  List<Map<String, dynamic>> _filteredSuppliers = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fetchSuppliers();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterSuppliers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 添加过滤供应商的方法
  void _filterSuppliers() {
    final searchText = _searchController.text.trim().toLowerCase();
    
    setState(() {
      if (searchText.isEmpty) {
        _filteredSuppliers = List.from(_suppliers);
        _isSearching = false;
      } else {
        _filteredSuppliers = _suppliers.where((supplier) {
          final name = supplier['name'].toString().toLowerCase();
          final note = (supplier['note'] ?? '').toString().toLowerCase();
          return name.contains(searchText) || note.contains(searchText);
        }).toList();
        _isSearching = true;
      }
    });
  }

  Future<void> _fetchSuppliers() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        // 只获取当前用户的供应商
        final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _suppliers = suppliers;
          _filteredSuppliers = suppliers; // 初始时过滤列表等于全部列表
        });
      }
    }
  }

  Future<void> _addSupplier() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SupplierDialog(),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 检查当前用户下供应商名称是否已存在
          final existingSupplier = await db.query(
            'suppliers',
            where: 'userId = ? AND name = ?',
            whereArgs: [userId, result['name']],
          );

          if (existingSupplier.isNotEmpty) {
            // 显示提示信息
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${result['name']} 已存在'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // 添加userId到供应商数据
            result['userId'] = userId;
            await db.insert('suppliers', result);
            _fetchSuppliers();
          }
        }
      }
    }
  }

  Future<void> _editSupplier(Map<String, dynamic> supplier) async {
    // 确保传递给对话框的是一个副本，避免引用问题
    final Map<String, dynamic> supplierCopy = Map<String, dynamic>.from(supplier);
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SupplierDialog(supplier: supplierCopy),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 检查当前用户下供应商名称是否已存在（排除当前编辑的供应商）
          final existingSupplier = await db.query(
            'suppliers',
            where: 'userId = ? AND name = ? AND id != ?',
            whereArgs: [userId, result['name'], supplier['id']],
          );

          if (existingSupplier.isNotEmpty) {
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
            await db.update('suppliers', result, where: 'id = ? AND userId = ?', whereArgs: [supplier['id'], userId]);
            _fetchSuppliers();
          }
        }
      }
    }
  }

  Future<void> _deleteSupplier(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('您确定要删除供应商 "$name" 吗？'),
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
          // 只删除当前用户的供应商
          await db.delete('suppliers', where: 'id = ? AND userId = ?', whereArgs: [id, userId]);
          // 更新当前用户的采购记录，将删除的供应商ID设为0
          await db.update(
            'purchases',
            {'supplierId': 0},
            where: 'supplierId = ? AND userId = ?',
            whereArgs: [id, userId],
          );
          _fetchSuppliers();
        }
      }
    }
  }

  void _viewSupplierRecords(int supplierId, String supplierName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierRecordsScreen(supplierId: supplierId, supplierName: supplierName),
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
          title: Text('供应商', style: TextStyle(
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
                  Icon(Icons.business, color: Colors.blue[700], size: 20),
                  SizedBox(width: 8),
                  Text(
                    '供应商列表',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                  Spacer(),
                  Text(
                    '共 ${_filteredSuppliers.length} 家供应商',
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
              child: _filteredSuppliers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.business_outlined, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            _isSearching ? '没有匹配的供应商' : '暂无供应商',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加供应商',
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
                      itemCount: _filteredSuppliers.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                        final supplier = _filteredSuppliers[index];
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
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.blue[100],
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Center(
                                      child: Text(
                                        supplier['name'].toString().isNotEmpty 
                                            ? supplier['name'].toString()[0].toUpperCase() 
                                            : '?',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue[800],
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          supplier['name'],
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if ((supplier['note'] ?? '').toString().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              supplier['note'],
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
                                        icon: Icon(Icons.list_alt, color: Colors.blue),
                                        tooltip: '查看记录',
                                        onPressed: () => _viewSupplierRecords(
                                          supplier['id'] as int, 
                                          supplier['name'] as String
                                        ),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                      ),
                                      SizedBox(width: 4),
                      IconButton(
                                        icon: Icon(Icons.edit, color: Colors.blue),
                                        tooltip: '编辑',
                        onPressed: () => _editSupplier(supplier),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                                      ),
                                      if (_showDeleteButtons)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: IconButton(
                                          icon: Icon(Icons.delete, color: Colors.red),
                                          tooltip: '删除',
                                          onPressed: () => _deleteSupplier(
                                            supplier['id'] as int, 
                                            supplier['name'] as String
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
                        hintText: '搜索供应商...',
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
                          borderSide: BorderSide(color: Colors.blue),
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
        onPressed: _addSupplier,
        child: Icon(Icons.add),
                    tooltip: '添加供应商',
                    backgroundColor: Colors.blue,
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

class SupplierDialog extends StatefulWidget {
  final Map<String, dynamic>? supplier;

  SupplierDialog({this.supplier});

  @override
  _SupplierDialogState createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<SupplierDialog> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.supplier != null) {
      _nameController.text = widget.supplier!['name'].toString();
      _noteController.text = (widget.supplier!['note'] ?? '').toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.supplier == null ? '添加供应商' : '编辑供应商',
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
                labelText: '供应商名称',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: Icon(Icons.business, color: Colors.blue),
          ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入供应商名称';
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
                prefixIcon: Icon(Icons.note, color: Colors.blue),
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
                  final Map<String, dynamic> supplier = {
                    'name': _nameController.text.trim(),
                    'note': _noteController.text.trim(),
                };
                  // 确保ID使用原始类型
                  if (widget.supplier != null && widget.supplier!.containsKey('id')) {
                    // 保留原始ID类型，不进行转换
                    supplier['id'] = widget.supplier!['id'];
                  }
                Navigator.of(context).pop(supplier);
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