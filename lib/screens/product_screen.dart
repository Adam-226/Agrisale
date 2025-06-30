// lib/screens/product_screen.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart'; // 确保路径正确
import 'package:shared_preferences/shared_preferences.dart';

class ProductScreen extends StatefulWidget {
  @override
  _ProductScreenState createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  List<Map<String, dynamic>> _products = [];
  bool _showDeleteButtons = false;

  // 添加搜索相关的状态变量
  List<Map<String, dynamic>> _filteredProducts = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 添加过滤产品的方法
  void _filterProducts() {
    final searchText = _searchController.text.trim().toLowerCase();
    
    setState(() {
      if (searchText.isEmpty) {
        _filteredProducts = List.from(_products);
        _isSearching = false;
      } else {
        _filteredProducts = _products.where((product) {
          final name = product['name'].toString().toLowerCase();
          final description = (product['description'] ?? '').toString().toLowerCase();
          return name.contains(searchText) || description.contains(searchText);
        }).toList();
        _isSearching = true;
      }
    });
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
          _filteredProducts = products;
        });
      }
    }
  }

  Future<void> _addProduct() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProductDialog(),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 检查当前用户下产品名称是否已存在
          final existingProduct = await db.query(
            'products',
            where: 'userId = ? AND name = ?',
            whereArgs: [userId, result['name']],
          );

          if (existingProduct.isNotEmpty) {
            // 显示提示信息
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${result['name']} 已存在'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // 添加userId到产品数据
            result['userId'] = userId;
            await db.insert('products', result);
            _fetchProducts();
          }
        }
      }
    }
  }

  Future<void> _editProduct(Map<String, dynamic> product) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProductDialog(product: product),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 检查当前用户下产品名称是否已存在（排除当前编辑的产品）
          final existingProduct = await db.query(
            'products',
            where: 'userId = ? AND name = ? AND id != ?',
            whereArgs: [userId, result['name'], product['id']],
          );

          if (existingProduct.isNotEmpty) {
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
            await db.update('products', result, where: 'id = ? AND userId = ?', whereArgs: [product['id'], userId]);
            _fetchProducts();
          }
        }
      }
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text(
          '您确定要删除以下产品吗？\n\n'
              '产品名称: ${product['name']}\n'
              '描述: ${product['description'] ?? '无描述'}\n'
              '库存: ${product['stock']} ${product['unit']}',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          // 保持原来的确认/取消按钮位置
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
          await db.delete('products', where: 'id = ? AND userId = ?', whereArgs: [product['id'], userId]);
          _fetchProducts();
        }
      }
    }
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
          title: Text('农资产品', style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )),
          actions: [
            IconButton(
              icon: Icon(_showDeleteButtons ? Icons.cancel : Icons.delete),
              tooltip: _showDeleteButtons ? '取消' : '显示删除按钮',
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
                  Icon(Icons.shopping_bag, color: Colors.green[700], size: 20),
                  SizedBox(width: 8),
                  Text(
                    '产品列表',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  Spacer(),
                  Text(
                    '共 ${_filteredProducts.length} 个品种',
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
              child: _filteredProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                          Icon(Icons.inventory, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            _isSearching ? '没有匹配的产品' : '暂无产品',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加产品',
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
                      itemCount: _filteredProducts.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
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
                                      color: Colors.green[100],
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Center(
                                      child: Text(
                                        product['name'].substring(0, 1),
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green[800],
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
                                          product['name'], 
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            '库存: ${product['stock']} ${product['unit']}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ),
                                        // 无论是否有备注，都保留相同高度的区域
                                        Container(
                                          height: 18, // 设置固定高度
                                          child: (product['description'] ?? '').toString().isNotEmpty
                                            ? Text(
                                                product['description'],
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                      ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              )
                                            : null, // 无备注时不显示内容，但保留高度
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 编辑按钮
                      IconButton(
                                    icon: Icon(Icons.edit, color: Colors.green),
                                    tooltip: '编辑',
                                    onPressed: () => _editProduct(product),
                                    constraints: BoxConstraints(),
                                    padding: EdgeInsets.all(8),
                                  ),
                                  // 删除按钮（仅在删除模式下显示）
                                  if (_showDeleteButtons)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: IconButton(
                                        icon: Icon(Icons.delete, color: Colors.red),
                                        tooltip: '删除',
                        onPressed: () => _deleteProduct(product),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                                      ),
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
                        hintText: '搜索产品...',
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
                          borderSide: BorderSide(color: Colors.green),
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
        onPressed: _addProduct,
        child: Icon(Icons.add),
                    tooltip: '添加产品',
                    backgroundColor: Colors.green,
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

class ProductDialog extends StatefulWidget {
  final Map<String, dynamic>? product;

  ProductDialog({this.product});

  @override
  _ProductDialogState createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stockController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _selectedUnit = '斤'; // 默认单位

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _nameController.text = widget.product!['name'];
      _descriptionController.text = widget.product!['description'] ?? '';
      _stockController.text = widget.product!['stock'].toString();
      _selectedUnit = widget.product!['unit'];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.product == null ? '添加产品' : '编辑产品',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
          children: [
              TextFormField(
              controller: _nameController,
                decoration: InputDecoration(
                  labelText: '产品名称',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.shopping_bag, color: Colors.green),
            ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入产品名称';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
              controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: '描述',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.description, color: Colors.green),
            ),
                maxLines: 2,
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
              controller: _stockController,
                      decoration: InputDecoration(
                        labelText: '库存',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: Icon(Icons.inventory, color: Colors.green),
                      ),
              keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入库存';
                        }
                        if (int.tryParse(value) == null) {
                          return '请输入有效数字';
                        }
                        return null;
                      },
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[400]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
              value: _selectedUnit,
                          isExpanded: true,
                          icon: Icon(Icons.arrow_drop_down, color: Colors.green),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedUnit = newValue!;
                });
              },
              items: <String>['斤', '公斤', '袋']
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
            ),
          ],
          ),
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      actions: [
        // 保持原来的保存/取消按钮位置
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                final product = {
                    'name': _nameController.text.trim(),
                    'description': _descriptionController.text.trim(),
                  'stock': int.tryParse(_stockController.text) ?? 0,
                  'unit': _selectedUnit,
                };
                  if (widget.product != null) {
                    product['id'] = widget.product!['id'];
                  }
                Navigator.of(context).pop(product);
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
    _descriptionController.dispose();
    _stockController.dispose();
    super.dispose();
  }
}