import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oidc/oidc.dart';
import '../error_messages.dart';
import '../profile_service.dart';
import '../providers.dart';
import '../ui_shared.dart';

class UserView extends ConsumerStatefulWidget {
  const UserView({super.key, required this.user});
  final OidcUser user;
  @override
  ConsumerState<UserView> createState() => _UserViewState();
}

class _UserViewState extends ConsumerState<UserView> {
  final _name = TextEditingController();
  final _nickname = TextEditingController();
  final _birthdate = TextEditingController();
  String _gender = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _registerFcmToken(); // CIBA 通知用に裏で登録 (画面には出さない)
    _loadProfile();
  }

  @override
  void dispose() {
    _name.dispose();
    _nickname.dispose();
    _birthdate.dispose();
    super.dispose();
  }

  String get _email {
    final ui = widget.user.userInfo['email'];
    if (ui is String && ui.isNotEmpty) return ui;
    final c = widget.user.claims.toJson()['email'];
    if (c is String && c.isNotEmpty) return c;
    return widget.user.uid ?? '';
  }

  Future<void> _registerFcmToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      final accessToken = widget.user.token.accessToken;
      if (fcmToken == null || accessToken == null) return;
      await ref.read(profileServiceProvider).registerFcmToken(accessToken, fcmToken);
    } catch (_) {
      // 失敗してもプロフィール画面は使えるので黙って無視。
    }
  }

  Future<void> _loadProfile() async {
    try {
      final accessToken = widget.user.token.accessToken;
      if (accessToken != null) {
        final p = await ref.read(profileServiceProvider).load(accessToken);
        if (p != null) {
          _name.text = p.name;
          _nickname.text = p.nickname;
          _birthdate.text = p.birthdate;
          _gender = p.gender;
        }
      }
    } catch (_) {
      // 読めなくても空で編集開始できる。
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final accessToken = widget.user.token.accessToken;
      if (accessToken == null) {
        throw Exception('セッションが切れました。ログインし直してください。');
      }
      await ref.read(profileServiceProvider).save(
            accessToken,
            ProfileData(
              name: _name.text,
              nickname: _nickname.text,
              gender: _gender,
              birthdate: _birthdate.text,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プロフィールを保存しました')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = humanizeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickBirthdate() async {
    final parsed = DateTime.tryParse(_birthdate.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final y = picked.year.toString().padLeft(4, '0');
      final m = picked.month.toString().padLeft(2, '0');
      final d = picked.day.toString().padLeft(2, '0');
      setState(() => _birthdate.text = '$y-$m-$d');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('プロフィール',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(_email, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          _FieldCard(
            key: cursorTargetKeys['name'],
            label: '氏名',
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                  hintText: '未設定', border: OutlineInputBorder()),
            ),
          ),
          _FieldCard(
            key: cursorTargetKeys['nickname'],
            label: 'ニックネーム',
            child: TextField(
              controller: _nickname,
              decoration: const InputDecoration(
                  hintText: '未設定', border: OutlineInputBorder()),
            ),
          ),
          _FieldCard(
            key: cursorTargetKeys['gender'],
            label: '性別',
            child: DropdownButtonFormField<String>(
              initialValue: _gender.isEmpty ? null : _gender,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              hint: const Text('未設定'),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('男性')),
                DropdownMenuItem(value: 'female', child: Text('女性')),
                DropdownMenuItem(value: 'other', child: Text('その他')),
              ],
              onChanged: (v) => setState(() => _gender = v ?? ''),
            ),
          ),
          _FieldCard(
            key: cursorTargetKeys['birthdate'],
            label: '誕生日',
            child: TextField(
              controller: _birthdate,
              readOnly: true,
              onTap: _pickBirthdate,
              decoration: const InputDecoration(
                hintText: '未設定',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            key: cursorTargetKeys['save'],
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('保存'),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            key: cursorTargetKeys['logout'],
            // ブラウザを開く RP-initiated ログアウトではなくローカルでトークンを破棄する。
            // ログインは毎回 prompt=login を強制するため、OP セッションが残っても
            // 勝手な自動ログインは起きない (= ブラウザの点滅を無くせる)。
            onPressed: () => ref.read(oidcManagerProvider).forgetUser(),
            icon: const Icon(Icons.logout),
            label: const Text('ログアウト'),
          ),
        ],
      ),
    );
  }
}

/// プロフィール 1 項目分のカード (ラベル + 入力 widget)。カーソル案内の対象。
class _FieldCard extends StatelessWidget {
  const _FieldCard({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
