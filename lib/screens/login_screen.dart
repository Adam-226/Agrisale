// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController(); // 注册时确认密码
  bool _obscurePassword = true; // 控制密码显示/隐藏
  bool _obscureConfirmPassword = true; // 控制确认密码显示/隐藏
  bool _isLoading = false; // 加载状态
  bool _isLoginMode = true; // true为登录模式，false为注册模式

  @override
  void initState() {
    super.initState();
    _loadLastUsername();
  }

  // 加载上次登录的用户名
  Future<void> _loadLastUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUsername = prefs.getString('last_username') ?? '';
    if (lastUsername.isNotEmpty) {
      _usernameController.text = lastUsername;
    }
  }

  // 切换登录/注册模式
  void _toggleMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
      _confirmPasswordController.clear(); // 切换时清空确认密码
    });
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入用户名和密码')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final db = await DatabaseHelper().database;
      final username = _usernameController.text;
      final password = _passwordController.text;

      final result = await db.query(
        'users',
        where: 'username = ? AND password = ?',
        whereArgs: [username, password],
      );

      if (result.isNotEmpty) {
        // 保存当前用户名和上次登录的用户名到SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('current_username', username);
        await prefs.setString('last_username', username);
        
        Navigator.pushReplacementNamed(context, '/main');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('用户名或密码错误'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _register() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty || _confirmPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请填写所有字段')),
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('两次输入的密码不一致')),
      );
      return;
    }

    if (_passwordController.text.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('密码长度至少为3个字符')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final db = await DatabaseHelper().database;
      final username = _usernameController.text;
      final password = _passwordController.text;

      // 检查用户名是否已存在
      final existingUser = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: [username],
      );

      if (existingUser.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('用户名已存在，请选择其他用户名'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 创建新用户
      final userId = await db.insert('users', {
        'username': username,
        'password': password,
      });

      // 为新用户创建设置记录
      await DatabaseHelper().createUserSettings(userId);

      // 保存用户名到SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_username', username);
      await prefs.setString('last_username', username);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('注册成功！'),
          backgroundColor: Colors.green,
        ),
      );

      // 注册成功后自动登录
      Navigator.pushReplacementNamed(context, '/main');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 80.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(height: 60), // 增加顶部间距
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/images/background.png',
                              width: 50,
                              height: 50,
                            ),
                            SizedBox(width: 10),
                            Text(
                              '农资管理系统',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 80), // 增加标题和卡片之间的间距
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            children: [
                              // 切换按钮
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          if (!_isLoginMode) _toggleMode();
                                        },
                                        child: Container(
                                          padding: EdgeInsets.symmetric(vertical: 12),
                                          decoration: BoxDecoration(
                                            color: _isLoginMode ? Colors.green : Colors.transparent,
                                            borderRadius: BorderRadius.circular(25),
                                          ),
                                          child: Text(
                                            '登录',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: _isLoginMode ? Colors.white : Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          if (_isLoginMode) _toggleMode();
                                        },
                                        child: Container(
                                          padding: EdgeInsets.symmetric(vertical: 12),
                                          decoration: BoxDecoration(
                                            color: !_isLoginMode ? Colors.green : Colors.transparent,
                                            borderRadius: BorderRadius.circular(25),
                                          ),
                                          child: Text(
                                            '注册',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: !_isLoginMode ? Colors.white : Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 24),
                              TextField(
                                controller: _usernameController,
                                decoration: InputDecoration(
                                  labelText: '用户名',
                                  prefixIcon: Icon(Icons.person, color: Colors.green),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              SizedBox(height: 20),
                              TextField(
                                controller: _passwordController,
                                decoration: InputDecoration(
                                  labelText: '密码',
                                  prefixIcon: Icon(Icons.lock, color: Colors.green),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                      color: Colors.green,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                obscureText: _obscurePassword,
                                onSubmitted: (_) => _isLoginMode ? _login() : null,
                              ),
                              // 注册模式下显示确认密码输入框
                              if (!_isLoginMode) ...[
                                SizedBox(height: 20),
                                TextField(
                                  controller: _confirmPasswordController,
                                  decoration: InputDecoration(
                                    labelText: '确认密码',
                                    prefixIcon: Icon(Icons.lock_outline, color: Colors.green),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                                        color: Colors.green,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscureConfirmPassword = !_obscureConfirmPassword;
                                        });
                                      },
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  obscureText: _obscureConfirmPassword,
                                  onSubmitted: (_) => _register(),
                                ),
                              ],
                              SizedBox(height: 30),
                              _isLoading
                                  ? CircularProgressIndicator()
                                  : ElevatedButton(
                                      onPressed: _isLoginMode ? _login : _register,
                                      child: Text(
                                        _isLoginMode ? '登录' : '注册',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: Size(double.infinity, 50),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
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
              ),
            ),
            FooterWidget(), // 保持脚标不变
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}