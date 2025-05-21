// Import the functions you need from the SDKs you need
import { initializeApp } from "firebase/app";
import { getAnalytics } from "firebase/analytics";
import { getDatabase } from "firebase/database";

// Your web app's Firebase configuration
const firebaseConfig = {
    apiKey: "AIzaSyBLc6VWE91Dm67Jck5hNOt_tlX7MsDHmdM",
    authDomain: "sheshiled-f0cc6.firebaseapp.com",
    projectId: "sheshiled-f0cc6",
    storageBucket: "sheshiled-f0cc6.firebasestorage.app",
    messagingSenderId: "653693267112",
    appId: "1:653693267112:web:adcb0a739738567fd4269d",
    measurementId: "G-G0MNH2TM1K",
    databaseURL: "https://sheshiled-f0cc6.firebaseio.com"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const analytics = getAnalytics(app);
const database = getDatabase(app);

export { app, analytics, database }; 