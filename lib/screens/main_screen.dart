// lib/screens/main_screen.dart

import 'package:flutter/material.dart';

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // 定义第一页的功能项
  final List<Map<String, dynamic>> _page1Items = [
    {
      'title': '基础功能',
      'items': [
        {'name': '农资产品', 'icon': Icons.inventory, 'route': '/products'},
        {'name': '采购', 'icon': Icons.shopping_cart, 'route': '/purchases'},
        {'name': '销售', 'icon': Icons.point_of_sale, 'route': '/sales'},
        {'name': '退货', 'icon': Icons.assignment_return, 'route': '/returns'},
      ]
    },
    {
      'title': '客户与供应商',
      'items': [
        {'name': '客户', 'icon': Icons.people, 'route': '/customers'},
        {'name': '供应商', 'icon': Icons.business, 'route': '/suppliers'},
      ]
    },
  ];

  // 定义第二页的功能项
  final List<Map<String, dynamic>> _page2Items = [
    {
      'title': '报告统计',
      'items': [
        {'name': '库存报告', 'icon': Icons.assessment, 'route': '/stock_report'},
        {'name': '采购报告', 'icon': Icons.receipt_long, 'route': '/purchase_report'},
        {'name': '销售报告', 'icon': Icons.bar_chart, 'route': '/sales_report'},
        {'name': '退货报告', 'icon': Icons.assignment_return, 'route': '/returns_report'},
        {'name': '总销售报告', 'icon': Icons.bar_chart, 'route': '/total_sales_report'},
        {'name': '财务统计', 'icon': Icons.attach_money, 'route': '/financial_statistics'},
      ]
    },
  ];

  // 定义第三页的功能项
  final List<Map<String, dynamic>> _page3Items = [
    {
      'title': '系统工具',
      'items': [
        {'name': '数据分析助手', 'icon': Icons.analytics, 'route': '/data_assistant'},
        {'name': '设置', 'icon': Icons.settings, 'route': '/settings'},
      ]
    },
  ];

  // 构建功能页面
  Widget _buildPage(List<Map<String, dynamic>> menuItems) {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: menuItems.length,
      itemBuilder: (context, groupIndex) {
        final group = menuItems[groupIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Text(
                group['title'],
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
            ),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: EdgeInsets.only(bottom: 16),
              child: ListView.separated(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: group['items'].length,
                separatorBuilder: (context, index) => Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = group['items'][index];
                  return ListTile(
                    leading: Icon(item['icon'], color: Colors.green),
                    title: Text(
                      item['name'],
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pushNamed(context, item['route']);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/background.png',
              width: 36,
              height: 36,
            ),
            SizedBox(width: 10),
            Text(
              '农资管理系统',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildPage(_page1Items),
          _buildPage(_page2Items),
          _buildPage(_page3Items),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.apps),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '',
          ),
        ],
      ),
    );
  }
}