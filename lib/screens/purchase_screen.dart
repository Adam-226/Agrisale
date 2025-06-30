// lib/screens/purchase_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PurchaseScreen extends StatefulWidget {
  @override
  _PurchaseScreenState createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _suppliers = [];
  bool _showDeleteButtons = false;
  
  // 添加搜索相关的状态变量
  List<Map<String, dynamic>> _filteredPurchases = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // 添加高级搜索相关变量
  bool _showAdvancedSearch = false;
  String? _selectedProductFilter;
  String? _selectedSupplierFilter;
  DateTimeRange? _selectedDateRange;
  final ValueNotifier<List<String>> _activeFilters = ValueNotifier<List<String>>([]);

  @override
  void initState() {
    super.initState();
    _fetchData();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterPurchases();
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
      _selectedProductFilter = null;
      _selectedSupplierFilter = null;
      _selectedDateRange = null;
      _searchController.clear();
      _activeFilters.value = [];
      _filteredPurchases = List.from(_purchases);
      _isSearching = false;
      _showAdvancedSearch = false;
    });
  }

  // 更新搜索条件并显示活跃的过滤条件
  void _updateActiveFilters() {
    List<String> filters = [];
    
    if (_selectedProductFilter != null) {
      filters.add('产品: $_selectedProductFilter');
    }
    
    if (_selectedSupplierFilter != null) {
      filters.add('供应商: $_selectedSupplierFilter');
    }
    
    if (_selectedDateRange != null) {
      String startDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
      String endDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
      filters.add('日期: $startDate 至 $endDate');
    }
    
    _activeFilters.value = filters;
  }

  // 添加过滤采购记录的方法 - 增强版
  void _filterPurchases() {
    final searchText = _searchController.text.trim();
    final searchTerms = searchText.toLowerCase().split(' ').where((term) => term.isNotEmpty).toList();
    
    setState(() {
      // 开始筛选
      List<Map<String, dynamic>> result = List.from(_purchases);
      bool hasFilters = false;
      
      // 关键词搜索
      if (searchTerms.isNotEmpty) {
        hasFilters = true;
        result = result.where((purchase) {
          final productName = purchase['productName'].toString().toLowerCase();
          final supplierName = _suppliers
              .firstWhere(
                (s) => s['id'] == purchase['supplierId'],
                orElse: () => {'name': ''},
              )['name']
              .toString()
              .toLowerCase();
          final date = purchase['purchaseDate'].toString().toLowerCase();
          final note = (purchase['note'] ?? '').toString().toLowerCase();
          final quantity = purchase['quantity'].toString().toLowerCase();
          final price = purchase['totalPurchasePrice'].toString().toLowerCase();
          
          // 检查所有搜索词是否都匹配
          return searchTerms.every((term) =>
            productName.contains(term) ||
            supplierName.contains(term) ||
            date.contains(term) ||
            note.contains(term) ||
            quantity.contains(term) ||
            price.contains(term)
          );
        }).toList();
      }
      
      // 产品筛选
      if (_selectedProductFilter != null) {
        hasFilters = true;
        result = result.where((purchase) => 
          purchase['productName'] == _selectedProductFilter).toList();
      }
      
      // 供应商筛选
      if (_selectedSupplierFilter != null) {
        hasFilters = true;
        final selectedSupplierId = _suppliers
            .firstWhere(
              (s) => s['name'] == _selectedSupplierFilter,
              orElse: () => {'id': -1},
            )['id'];
        
        result = result.where((purchase) => 
          purchase['supplierId'] == selectedSupplierId).toList();
      }
      
      // 日期范围筛选
      if (_selectedDateRange != null) {
        hasFilters = true;
        result = result.where((purchase) {
          final purchaseDate = DateTime.parse(purchase['purchaseDate']);
          return purchaseDate.isAfter(_selectedDateRange!.start.subtract(Duration(days: 1))) &&
                 purchaseDate.isBefore(_selectedDateRange!.end.add(Duration(days: 1)));
        }).toList();
      }
      
      _isSearching = hasFilters;
      _filteredPurchases = result;
      _updateActiveFilters();
    });
  }

  Future<void> _fetchData() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        // 只获取当前用户的数据
        final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);
        final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        final purchases = await db.query('purchases', where: 'userId = ?', whereArgs: [userId], orderBy: 'id DESC');
        
        setState(() {
          _products = products;
          _suppliers = suppliers;
          _purchases = purchases;
          _filteredPurchases = purchases; // 初始时过滤列表等于全部列表
        });
      }
    }
  }

  Future<void> _addPurchase() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PurchaseDialog(products: _products, suppliers: _suppliers),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 添加userId到采购记录
          result['userId'] = userId;
          await db.insert('purchases', result);

          // Update product stock - 确保只更新当前用户的产品
          final product = _products.firstWhere((p) => p['name'] == result['productName']);
          final newStock = product['stock'] + result['quantity'];
          await db.update(
            'products',
            {'stock': newStock},
            where: 'id = ? AND userId = ?',
            whereArgs: [product['id'], userId],
          );

          _fetchData();
        }
      }
    }
  }

  void _showNoteDialog(Map<String, dynamic> purchase) {
    final _noteController = TextEditingController(text: purchase['note']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('备注'),
        content: TextField(
          controller: _noteController,
          decoration: InputDecoration(
            labelText: '编辑备注',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          maxLines: null,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () async {
                  final db = await DatabaseHelper().database;
                  final prefs = await SharedPreferences.getInstance();
                  final username = prefs.getString('current_username');
                  
                  if (username != null) {
                    final userId = await DatabaseHelper().getCurrentUserId(username);
                    if (userId != null) {
                      await db.update(
                        'purchases',
                        {'note': _noteController.text},
                        where: 'id = ? AND userId = ?',
                        whereArgs: [purchase['id'], userId],
                      );
                      Navigator.of(context).pop();
                      _fetchData(); // Refresh data
                    }
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
      ),
    );
  }

  Future<void> _deletePurchase(Map<String, dynamic> purchase) async {
    final supplier = _suppliers.firstWhere(
          (s) => s['id'] == purchase['supplierId'],
      orElse: () => {'name': '未知供应商'},
    );
    final product = _products.firstWhere(
      (p) => p['name'] == purchase['productName'],
      orElse: () => {'unit': ''},
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text(
          '您确定要删除以下采购记录吗？\n\n'
              '产品名称: ${purchase['productName']}\n'
              '数量: ${purchase['quantity']} ${product['unit']}\n'
              '供应商: ${supplier['name']}\n'
              '日期: ${purchase['purchaseDate']}',
        ),
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
          // 只删除当前用户的采购记录
          await db.delete('purchases', where: 'id = ? AND userId = ?', whereArgs: [purchase['id'], userId]);

          // Rollback stock - 确保只更新当前用户的产品
          final newStock = product['stock'] - purchase['quantity'];
          await db.update(
            'products',
            {'stock': newStock},
            where: 'id = ? AND userId = ?',
            whereArgs: [product['id'], userId],
          );

          _fetchData();
        }
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('错误'),
        content: Text(message),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  // 显示高级搜索对话框
  void _showAdvancedSearchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,  // 添加此行以支持更大的高度
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(  // 添加滚动视图
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
                    
                    // 产品筛选
                    Text('按产品筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedProductFilter,
                        hint: Text('选择产品'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部产品'),
                          ),
                          ..._products.map((product) => DropdownMenuItem<String?>(
                            value: product['name'],
                            child: Text(product['name']),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedProductFilter = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // 供应商筛选
                    Text('按供应商筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedSupplierFilter,
                        hint: Text('选择供应商'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部供应商'),
                          ),
                          ..._suppliers.map((supplier) => DropdownMenuItem<String?>(
                            value: supplier['name'],
                            child: Text(supplier['name']),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedSupplierFilter = value;
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
                                  primary: Colors.green,
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
                    Padding(  // 添加底部内边距
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 20
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,  // 设定按钮高度
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _filterPurchases();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
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
          title: Text('采购', style: TextStyle(
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
          Expanded(
              child: _filteredPurchases.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_cart, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            _isSearching ? '没有匹配的采购记录' : '暂无采购记录',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加采购记录',
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
                      itemCount: _filteredPurchases.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                        final purchase = _filteredPurchases[index];
                final supplier = _suppliers.firstWhere(
                      (s) => s['id'] == purchase['supplierId'],
                  orElse: () => {'name': '未知供应商'},
                );
                final product = _products.firstWhere(
                      (p) => p['name'] == purchase['productName'],
                  orElse: () => {'unit': ''},
                );
                        
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        purchase['productName'],
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          purchase['purchaseDate'],
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(Icons.note_alt_outlined, color: Colors.blue),
                                              tooltip: '编辑备注',
                                              onPressed: () => _showNoteDialog(purchase),
                                              padding: EdgeInsets.zero,
                                              constraints: BoxConstraints(),
                                              iconSize: 18,
                                            ),
                                            if (_showDeleteButtons)
                                              Padding(
                                                padding: const EdgeInsets.only(left: 8),
                                                child: IconButton(
                                                  icon: Icon(Icons.delete, color: Colors.red),
                                                  tooltip: '删除',
                                                  onPressed: () => _deletePurchase(purchase),
                                                  padding: EdgeInsets.zero,
                                                  constraints: BoxConstraints(),
                                                  iconSize: 18,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.business, 
                                         size: 14, 
                                         color: Colors.blue[700]),
                                    SizedBox(width: 4),
                                    Text(
                                      '供应商: ${supplier['name']}',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.inventory_2, 
                                         size: 14, 
                                         color: Colors.green[700]),
                                    SizedBox(width: 4),
                                    Text(
                                      '数量: ${purchase['quantity']} ${product['unit']}',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.attach_money, 
                                         size: 14, 
                                         color: Colors.amber[700]),
                                    SizedBox(width: 4),
                                    Text(
                                      '总进价: ${purchase['totalPurchasePrice']}',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                                if (purchase['note'] != null && purchase['note'].toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Row(
                                      children: [
                                        Icon(Icons.note, 
                                             size: 14, 
                                             color: Colors.grey[600]),
                                        SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '备注: ${purchase['note']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[700],
                                              fontStyle: FontStyle.italic,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                SizedBox(height: 4),
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
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[100]!)
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.filter_list, size: 16, color: Colors.green),
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
                                        backgroundColor: Colors.green[100],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.clear, size: 16, color: Colors.green),
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
                            hintText: '搜索采购记录...',
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
                      SizedBox(width: 8),
                      // 高级搜索按钮
                      IconButton(
                        onPressed: _showAdvancedSearchDialog,
                        icon: Icon(
                          Icons.tune,
                          color: _showAdvancedSearch ? Colors.green : Colors.grey[600],
                          size: 20,
                      ),
                        tooltip: '高级搜索',
                      ),
                      SizedBox(width: 8),
                      // 添加按钮
                      FloatingActionButton(
                        onPressed: _addPurchase,
                        child: Icon(Icons.add),
                        tooltip: '添加采购',
                        backgroundColor: Colors.green,
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

class PurchaseDialog extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> suppliers;

  PurchaseDialog({required this.products, required this.suppliers});

  @override
  _PurchaseDialogState createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<PurchaseDialog> {
  String? _selectedProduct;
  String? _selectedSupplier;
  final _quantityController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  double _totalPurchasePrice = 0.0;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.green,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate)
      setState(() {
        _selectedDate = picked;
      });
  }

  void _calculateTotalPrice() {
    final purchasePrice = double.tryParse(_purchasePriceController.text) ?? 0.0;
    final quantity = int.tryParse(_quantityController.text) ?? 0;
    setState(() {
      _totalPurchasePrice = purchasePrice * quantity;
    });
  }

  @override
  Widget build(BuildContext context) {
    String unit = '';
    if (_selectedProduct != null) {
      final product = widget.products.firstWhere((p) => p['name'] == _selectedProduct);
      unit = product['unit'];
    }

    return AlertDialog(
      title: Text(
        '添加采购',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedProduct,
                decoration: InputDecoration(
                  labelText: '选择产品',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.inventory, color: Colors.green),
                ),
                isExpanded: true,
              items: widget.products.map((product) {
                return DropdownMenuItem<String>(
                  value: product['name'],
                  child: Text(product['name']),
                );
              }).toList(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请选择产品';
                  }
                  return null;
                },
              onChanged: (value) {
                setState(() {
                  _selectedProduct = value;
                });
              },
            ),
              SizedBox(height: 16),
              
            DropdownButtonFormField<String>(
              value: _selectedSupplier,
                decoration: InputDecoration(
                  labelText: '选择供应商',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.business, color: Colors.green),
                ),
                isExpanded: true,
              items: widget.suppliers.map((supplier) {
                return DropdownMenuItem<String>(
                  value: supplier['id'].toString(),
                  child: Text(supplier['name']),
                );
              }).toList(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请选择供应商';
                  }
                  return null;
                },
              onChanged: (value) {
                setState(() {
                  _selectedSupplier = value;
                });
              },
            ),
              SizedBox(height: 16),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
              controller: _quantityController,
                      decoration: InputDecoration(
                        labelText: '数量',
                        helperText: unit.isNotEmpty ? '单位: $unit' : '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: Icon(Icons.format_list_numbered, color: Colors.green),
                      ),
              keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入数量';
                        }
                        if (int.tryParse(value) == null) {
                          return '请输入有效数字';
                        }
                        return null;
                      },
              onChanged: (value) => _calculateTotalPrice(),
            ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
              controller: _purchasePriceController,
                      decoration: InputDecoration(
                        labelText: '进价',
                        helperText: unit.isNotEmpty ? '元/$unit' : '元/单位',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: Icon(Icons.attach_money, color: Colors.green),
                      ),
              keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入进价';
                        }
                        if (double.tryParse(value) == null) {
                          return '请输入有效数字';
                        }
                        return null;
                      },
              onChanged: (value) => _calculateTotalPrice(),
            ),
                  ),
                ],
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
                  prefixIcon: Icon(Icons.note, color: Colors.green),
                ),
                maxLines: 2,
            ),
              SizedBox(height: 16),
              
              InkWell(
                onTap: () => _selectDate(context),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: '采购日期',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    prefixIcon: Icon(Icons.calendar_today, color: Colors.green),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                      Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
                      Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
              
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[100]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '总进价:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '¥ $_totalPurchasePrice',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                ),
              ],
            ),
              ),
          ],
          ),
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                final purchase = {
                  'productName': _selectedProduct,
                  'quantity': int.tryParse(_quantityController.text) ?? 0,
                    'supplierId': int.tryParse(_selectedSupplier ?? '') ?? 0,
                  'purchaseDate': DateFormat('yyyy-MM-dd').format(_selectedDate),
                  'totalPurchasePrice': _totalPurchasePrice,
                    'note': _noteController.text,
                };
                Navigator.of(context).pop(purchase);
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