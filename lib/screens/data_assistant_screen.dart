import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 导入剪贴板功能
import 'package:http/http.dart' as http;
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DataAssistantScreen extends StatefulWidget {
  @override
  _DataAssistantScreenState createState() => _DataAssistantScreenState();
}

class _DataAssistantScreenState extends State<DataAssistantScreen> {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  List<Map<String, dynamic>> _chatHistory = [];

  @override
  void initState() {
    super.initState();
    _addSystemMessage("欢迎使用数据分析助手！您可以询问关于系统中的产品、销售、采购、库存等数据的问题。");
  }

  void _addSystemMessage(String message) {
    setState(() {
      _chatHistory.add({
        'role': 'system',
        'content': message,
      });
    });
  }

  void _addUserMessage(String message) {
    setState(() {
      _chatHistory.add({
        'role': 'user',
        'content': message,
      });
    });
  }

  void _addAssistantMessage(String message) {
    setState(() {
      _chatHistory.add({
        'role': 'assistant',
        'content': message,
      });
      _isLoading = false;
    });
    
    // 滚动到底部
    Future.delayed(Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 复制文本到剪贴板
  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('文本已复制到剪贴板'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchSystemData() async {
    final db = await DatabaseHelper().database;
    
    // 获取当前用户ID
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    if (username == null) {
      return {'error': '用户未登录'};
    }
    
    final userId = await DatabaseHelper().getCurrentUserId(username);
    if (userId == null) {
      return {'error': '用户信息错误'};
    }
    
    // 获取当前用户的产品数据
    final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);
    
    // 获取当前用户的销售数据
    final sales = await db.query('sales', where: 'userId = ?', whereArgs: [userId]);
    
    // 获取当前用户的采购数据
    final purchases = await db.query('purchases', where: 'userId = ?', whereArgs: [userId]);
    
    // 获取当前用户的退货数据
    final returns = await db.query('returns', where: 'userId = ?', whereArgs: [userId]);
    
    // 获取当前用户的客户数据
    final customers = await db.query('customers', where: 'userId = ?', whereArgs: [userId]);
    
    // 获取当前用户的供应商数据
    final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
    
    // 获取用户数据（出于安全考虑，不包含密码）
    final List<Map<String, dynamic>> users = await db.query('users', where: 'id = ?', whereArgs: [userId]);
    final safeUsers = users.map((user) => {
      'id': user['id'],
      'username': user['username'],
      // 不包含密码
    }).toList();
    
    // 数据库结构信息
    final dbStructure = {
      'tables': [
        {
          'name': 'users',
          'columns': ['id', 'username', 'password'],
          'description': '系统用户表，存储登录凭证'
        },
        {
          'name': 'products',
          'columns': ['id', 'userId', 'name', 'description', 'stock', 'unit'],
          'description': '产品表，存储农资产品信息，单位可以是斤、公斤或袋，每个用户有独立的产品数据'
        },
        {
          'name': 'suppliers',
          'columns': ['id', 'userId', 'name', 'note'],
          'description': '供应商表，存储产品供应商信息，每个用户有独立的供应商数据'
        },
        {
          'name': 'customers',
          'columns': ['id', 'userId', 'name', 'note'],
          'description': '客户表，存储客户信息，每个用户有独立的客户数据'
        },
        {
          'name': 'purchases',
          'columns': ['id', 'userId', 'productName', 'quantity', 'purchaseDate', 'supplierId', 'totalPurchasePrice', 'note'],
          'description': '采购记录表，记录产品进货信息，每个用户有独立的采购记录'
        },
        {
          'name': 'sales',
          'columns': ['id', 'userId', 'productName', 'quantity', 'customerId', 'saleDate', 'totalSalePrice', 'note'],
          'description': '销售记录表，记录产品销售信息，每个用户有独立的销售记录'
        },
        {
          'name': 'returns',
          'columns': ['id', 'userId', 'productName', 'quantity', 'customerId', 'returnDate', 'totalReturnPrice', 'note'],
          'description': '退货记录表，记录产品退货信息，每个用户有独立的退货记录'
        }
      ]
    };
    
    // 构建系统数据摘要
    return {
      'databaseStructure': dbStructure,
      'products': products,
      'sales': sales,
      'purchases': purchases,
      'returns': returns,
      'customers': customers,
      'suppliers': suppliers,
      'users': safeUsers,
      'currentUser': username,
    };
  }

  Future<void> _sendQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;
    
    _addUserMessage(question);
    _questionController.clear();
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 获取用户的模型设置，包括API Key
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username == null) {
        _addAssistantMessage('请先登录系统。');
        return;
      }
      
      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      
      if (userId == null) {
        _addAssistantMessage('用户信息错误，请重新登录。');
        return;
      }
      
      final settingsResult = await db.query(
        'user_settings',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      if (settingsResult.isEmpty) {
        _addAssistantMessage('请先在设置中配置您的DeepSeek API Key。');
        return;
      }
      
      final settings = settingsResult.first;
      final apiKey = (settings['deepseek_api_key'] as String?) ?? '';
      final temperature = (settings['deepseek_temperature'] as double?) ?? 0.7;
      final maxTokens = (settings['deepseek_max_tokens'] as int?) ?? 2000;
      final model = (settings['deepseek_model'] as String?) ?? 'deepseek-chat';
      
      // 验证API Key是否存在
      if (apiKey.isEmpty) {
        _addAssistantMessage('请先在设置中配置您的DeepSeek API Key。');
        return;
      }
      
      // 获取系统数据
      final systemData = await _fetchSystemData();
      final systemDataJson = jsonEncode(systemData);
      
      // 构建提示词
      final messages = [
        {
          'role': 'system',
          'content': '''
你是农资管理系统的数据分析助手。你可以分析系统中的产品、销售、采购、库存等数据，并回答用户的问题。

系统包含以下数据表：
1. users - 系统用户表
2. products - 产品表（包含名称、描述、库存、单位）
3. suppliers - 供应商表
4. customers - 客户表
5. purchases - 采购记录表
6. sales - 销售记录表
7. returns - 退货记录表

请根据用户提问，分析相关数据并提供专业、准确的回答。请以中文回复用户的所有问题，确保回复是有意义且可读的中文文本。

系统数据和结构：
$systemDataJson
'''
        }
      ];
      
      // 添加聊天历史
      for (final message in _chatHistory) {
        if (message['role'] != 'system') {
          messages.add({
            'role': message['role'],
            'content': message['content'],
          });
        }
      }
      
      // 发送API请求，使用用户设置的参数
      final response = await http.post(
        Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': temperature,
          'max_tokens': maxTokens,
          'response_format': {'type': 'text'}, // 确保响应为纯文本
        }),
      ).timeout(
        Duration(seconds: 30), // 30秒超时
        onTimeout: () {
          throw Exception('请求超时：DeepSeek API响应时间过长，请稍后重试');
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final assistantResponse = data['choices'][0]['message']['content'];
        _addAssistantMessage(assistantResponse);
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        _addAssistantMessage('抱歉，API请求失败。\n错误代码: ${response.statusCode}\n错误详情: $errorBody');
      }
    } catch (e) {
      String errorMessage = '抱歉，发生了错误: ';
      
      // 根据错误类型提供更具体的错误信息
      if (e.toString().contains('Connection failed') || 
          e.toString().contains('SocketException') ||
          e.toString().contains('Network is unreachable')) {
        errorMessage += '网络连接失败，请检查：\n' +
                       '1. 网络连接是否正常\n' +
                       '2. 是否使用了代理服务器\n' +
                       '3. API密钥是否正确\n' +
                       '4. 防火墙是否阻止了连接\n\n' +
                       '详细错误: $e';
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage += '请求超时，请稍后重试。\n详细错误: $e';
      } else if (e.toString().contains('FormatException')) {
        errorMessage += 'API响应格式错误。\n详细错误: $e';
      } else {
        errorMessage += '$e';
             }
       
       _addAssistantMessage(errorMessage);
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '数据分析助手',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.grey[100],
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(16),
                itemCount: _chatHistory.length,
                itemBuilder: (context, index) {
                  final message = _chatHistory[index];
                  final isUser = message['role'] == 'user';
                  
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: GestureDetector(
                      onLongPress: () {
                        _copyToClipboard(message['content']);
                      },
                      child: Container(
                        margin: EdgeInsets.symmetric(vertical: 8),
                        padding: EdgeInsets.all(12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isUser ? Colors.green[100] : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            SelectableText(  // 使用SelectableText代替Text，允许选择文本
                              message['content'],
                              style: TextStyle(
                                fontSize: 16,
                                color: isUser ? Colors.green[900] : Colors.black87,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: InkWell(
                                onTap: () => _copyToClipboard(message['content']),
                                child: Container(
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(
                                    Icons.copy,
                                    size: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
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
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('正在分析数据...'),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 3,
                  offset: Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    decoration: InputDecoration(
                      hintText: '请输入您的问题...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    minLines: 1,
                    maxLines: 5,
                    onSubmitted: (_) => _sendQuestion(),
                  ),
                ),
                SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _sendQuestion,
                  child: Icon(Icons.send),
                  mini: true,
                  backgroundColor: Colors.green,
                ),
              ],
            ),
          ),
          FooterWidget(),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
} 