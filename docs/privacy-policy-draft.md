# N2IT Solutions Privacy Policy (draft)

Oct 13, 2026 · @N2IT Support

## Review notes (delete before publishing)

The current policy ([privacy-policy.pdf](https://www.n2it.co.za/privacy-policy.pdf), last changed December 2021) does not cover the phone apps or the hosted PBX. Apple needs a privacy policy URL for TestFlight external testing and for the App Store, and it must describe what the app collects.

Gaps in the 2021 policy:

| Gap | Why it matters |
| --- | --- |
| No mention of N2IT Phone (iPhone or Android) | Apple reviewers check the policy against the app |
| Push tokens sent to Apple (USA) not covered | POPIA section 72 covers sending personal information outside South Africa |
| Call records, voicemail and recordings on the PBX not covered | This is the main personal information N2IT holds for clients |
| No retention periods, no data subject rights, no Information Officer or Information Regulator details | Required under POPIA |
| Mentions advertisers, a "personalise function" and "52% males" | None of these apply to N2IT; remove them |
| Published as a PDF | Apple accepts a PDF link, but a normal web page at /privacy is easier to keep current |

Confirm with the Apple side before publishing:

- [ ] Does the app read the phone's contacts, or only show its own call list?
- [ ] Does the app use any crash reporting or analytics service? This draft says it does not.
- [ ] Is the call history stored on the phone only, and are the sign-in details kept in the iPhone Keychain (as section 3 says)?
- [ ] Does the Android app use push (Firebase), or does it only ring while open?
- [ ] Who is N2IT's registered Information Officer, and which email should requests go to?
- [ ] Are calls recorded for any clients? (The PBX has call recording available.)

Facts in this draft were taken from the PBX server code on 13 October 2026: the push sign-in service, the push sender and the iPhone registration page.

## 1. Who we are and what this policy covers

N2IT Solutions ("N2IT", "we") is the responsible party for the personal information described here, under the Protection of Personal Information Act 4 of 2013 (POPIA). We respect your privacy and never sell your personal information or share it with advertisers.

This policy covers:

- our website, www.n2it.co.za
- our hosted phone system (PBX) at voip.n2it.co.za, including its web portal
- the N2IT Phone app for iPhone and Android
- the iPhone registration page used to install test versions of N2IT Phone

N2IT Phone is for staff of businesses that use N2IT's phone system. Your employer gives you your extension and password. If your employer is our client, they decide how their phone system is used, and we process call information on their behalf.

## 2. Our website

You can browse our website without telling us who you are. The site uses cookies to remember your preferences and to count visits. You can set your browser to refuse cookies. If you contact us through the website, we use your details only to answer you.

## 3. The N2IT Phone app

N2IT Phone lets you make and take calls on your company extension from your phone. It collects only what it needs to do that. It has no adverts, no tracking and no analytics.

| Information | Why we use it | Where it is kept |
| --- | --- | --- |
| Company code, extension number and extension password | To sign you in to your company's phone system | On your phone (iPhone Keychain or Android secure storage), and on our PBX as part of your extension |
| Push token (a random code Apple gives your iPhone) | To wake the app and ring your phone when it is locked | On our PBX, linked to your extension, until you sign out or it stops working |
| Phone numbers and names of callers, and the people you call | To connect calls and show who is calling | Shown on your phone and in the phone's call list; call records are kept on our PBX |
| The sound of your calls | To carry the call | Sent live over an encrypted connection, not stored, unless your company turned on call recording |
| Your phone's IP address and app version | To connect calls, stop password guessing and fix faults | In our PBX logs |

Permissions the app asks for:

- **Microphone**: so the other person can hear you during a call. It is used only while a call is in progress.
- **Notifications and calls (iPhone CallKit)**: so incoming calls ring like normal phone calls, also when the phone is locked.

The app does not collect your location, contacts, photos, browsing or other apps' data. It does not track you across other companies' apps or websites.

**Push notifications.** When someone calls your extension and your iPhone is locked, our PBX sends a wake-up message through Apple Push Notification service. The message contains the caller's name and number and your extension number, so your phone can show who is calling.

**Signing out.** When you sign out, the app deletes your sign-in details from the phone and our PBX deletes its push token. Deleting the app also removes everything it stored on the phone.

## 4. iPhone registration for test versions

Before N2IT Phone is on the App Store, we install test versions on registered iPhones. If you register on voip.n2it.co.za/download, we collect your name, company, extension (optional), your iPhone's device ID (UDID), model, iOS version and device name, and your IP address. We use these only to add your iPhone to Apple's list of test devices. The registration profile is not left on your phone.

## 5. Who we share information with

We do not sell personal information or share it for advertising. We share it only:

- with **Apple** (Apple Push Notification service and TestFlight), to ring locked iPhones and to install test versions of the app
- with the **telephone network providers** that carry calls to and from outside numbers, which receive the numbers needed to connect each call
- with **your employer**, if they are our client, who can see call records and voicemail for their own extensions
- when the law requires it

**Outside South Africa.** Apple processes push messages and test-device details in the United States. Under POPIA section 72, we send this information only to the extent needed for these services. Apple is bound by its own privacy terms and data protection law.

## 6. How we protect information

Our PBX runs on servers that N2IT manages. Sign-in and push requests use encrypted connections (HTTPS). Signing in to the push service needs the extension password, and repeated wrong passwords are blocked. Push tokens and registration records are kept outside the public web folders and only the service can read them.

## 7. How long we keep it

| Information | Kept for |
| --- | --- |
| Push token | Until you sign out, or Apple reports it is no longer valid |
| iPhone registration (UDID) records | Until the app is on the App Store, or you ask us to remove them |
| Call records, voicemail and any call recordings | As agreed with your employer, and as long as the law requires |
| Server logs | A limited time, for security and fault finding |

## 8. Your rights

Under POPIA you can ask us to:

- tell you what personal information we hold about you, and give you a copy
- correct information that is wrong
- delete information we no longer need
- stop using your information for a purpose you object to

To stop using N2IT Phone, sign out of the app and delete it. To remove your iPhone registration or other details, email us. If your extension belongs to your employer, we may also involve them.

## 9. Contact us and complaints

Information Officer, N2IT Solutions: support@n2it.co.za

If you are not happy with how we handled your request, you can complain to the Information Regulator (South Africa): [inforegulator.org.za](https://inforegulator.org.za), complaints.IR@inforegulator.org.za.

## 10. Changes to this policy

We will update this page when our services change. The date at the top shows the latest version.
