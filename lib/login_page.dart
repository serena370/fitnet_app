import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

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
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
                children: [LoginForm(), SignupForm()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

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
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message ?? "Login failed")),
                    );
                  }

                  if (!mounted) return;
                  setState(() => isLoading = false);
                },
          child: isLoading ? CircularProgressIndicator() : Text("Login"),
        ),
      ],
    );
  }
}

class SignupForm extends StatefulWidget {
  const SignupForm({super.key});

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

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    age.dispose();
    height.dispose();
    goalWeight.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> signup() async {
    setState(() => isLoading = true);

    try {
      // 1. Create Auth user
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email.text.trim(),
            password: password.text.trim(),
          );

      final uid = userCredential.user!.uid;

      // 2. Save profile in Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'firstName': firstName.text.trim(),
        'lastName': lastName.text.trim(),
        'age': int.tryParse(age.text),
        'height': double.tryParse(height.text),
        'goalWeight': double.tryParse(goalWeight.text),
        'createdAt': DateTime.now(),
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? "Signup failed")));
    }

    if (!mounted) return;
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          TextField(
            controller: firstName,
            decoration: InputDecoration(labelText: "First Name"),
          ),
          TextField(
            controller: lastName,
            decoration: InputDecoration(labelText: "Last Name"),
          ),
          TextField(
            controller: age,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: "Age"),
          ),
          TextField(
            controller: height,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: "Height (m)"),
          ),
          TextField(
            controller: goalWeight,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: "Goal Weight (kg)"),
          ),

          TextField(
            controller: email,
            decoration: InputDecoration(labelText: "Email"),
          ),
          TextField(
            controller: password,
            obscureText: true,
            decoration: InputDecoration(labelText: "Password"),
          ),

          SizedBox(height: 20),

          ElevatedButton(
            onPressed: isLoading ? null : signup,
            child: isLoading
                ? CircularProgressIndicator()
                : Text("Create Account"),
          ),
        ],
      ),
    );
  }
}
