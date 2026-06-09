import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  bool isLoading = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "FitNet",
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: "Login"),
                Tab(text: "Sign Up"),
              ],
            ),
            SizedBox(height: 20),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  LoginForm(),
                  SignupForm(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginForm extends StatefulWidget {
  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: emailController,
          decoration: InputDecoration(labelText: "Email"),
        ),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: InputDecoration(labelText: "Password"),
        ),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: isLoading
              ? null
              : () async {
                  setState(() => isLoading = true);
                  try {
                    await FirebaseAuth.instance.signInWithEmailAndPassword(
                      email: emailController.text.trim(),
                      password: passwordController.text.trim(),
                    );
                  } on FirebaseAuthException catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message ?? "Login failed")),
                    );
                  }
                  setState(() => isLoading = false);
                },
          child: isLoading ? CircularProgressIndicator() : Text("Login"),
        ),
      ],
    );
  }
}

class SignupForm extends StatefulWidget {
  @override
  State<SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends State<SignupForm> {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final age = TextEditingController();
  final height = TextEditingController();
  final goalWeight = TextEditingController();

  final email = TextEditingController();
  final password = TextEditingController();

  bool isLoading = false;

  Future<void> signup() async {
    setState(() => isLoading = true);

    try {
      // 1. Create Auth user
      final userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text.trim(),
      );

      final uid = userCredential.user!.uid;

      // 2. Save profile in Firestore (including email)
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'firstName': firstName.text.trim(),
        'lastName': lastName.text.trim(),
        'email': email.text.trim(),
        'age': int.tryParse(age.text),
        'height': double.tryParse(height.text),
        'goalWeight': double.tryParse(goalWeight.text),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Signup failed")),
      );
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          TextField(
              controller: firstName,
              decoration: InputDecoration(labelText: "First Name")),
          TextField(
              controller: lastName,
              decoration: InputDecoration(labelText: "Last Name")),
          TextField(
              controller: age,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: "Age")),
          TextField(
              controller: height,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: "Height (m)")),
          TextField(
              controller: goalWeight,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: "Goal Weight (kg)")),
          TextField(
              controller: email, decoration: InputDecoration(labelText: "Email")),
          TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(labelText: "Password")),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: isLoading ? null : signup,
            child: isLoading ? CircularProgressIndicator() : Text("Create Account"),
          ),
        ],
      ),
    );
  }
}
