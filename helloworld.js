// helloworld.js
const express = require('express');
const app = express();

app.get('/', (req, res) => {
  res.send('Hello World');
});

// 테스트용으로 app 내보내기
module.exports = app;

// 직접 실행할 때만 서버 시작
if (require.main === module) {
  app.listen(3000, () => {
    console.log('Server running');
  });
}

