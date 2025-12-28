// test/hellowolrd_test.js
const request = require('supertest');
const assert = require('assert');
const app = require('../helloworld'); // Express 앱 인스턴스

const server = app.listen(); // ← 여기서 서버 객체 생성

describe('main page', function () {
  after(function () {
    server.close(); // 테스트 끝나면 서버 종료
  });

  it('should say hello world', function (done) {
    request(server)
      .get('/')
      .expect(200)
      .expect((res) => {
        assert.strictEqual(res.text.trim(), 'Hello World');
      })
      .end(done);
  });
});

