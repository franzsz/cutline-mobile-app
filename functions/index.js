const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

// ✅ Replace with your real Gmail & App Password
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: "your-email@gmail.com",       // <-- YOUR Gmail here
    pass: "your-app-password",          // <-- Gmail App Password here
  },
});

exports.sendVerificationCode = functions.https.onCall(async (data, context) => {
  const { email, code } = data;

  const mailOptions = {
    from: "CutLine App <your-email@gmail.com>",
    to: email,
    subject: "Your CutLine Verification Code",
    text: `Your CutLine verification code is: ${code}\nThis code will expire in 5 minutes.`,
  };

  try {
    await transporter.sendMail(mailOptions);
    console.log("Email sent to", email);
    return { success: true };
  } catch (error) {
    console.error("Failed to send email:", error);
    throw new functions.https.HttpsError("internal", "Failed to send email");
  }
});
