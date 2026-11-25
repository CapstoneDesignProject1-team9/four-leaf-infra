"""Four-Leaf 백엔드 부하테스트.

실행: uvx locust -f loadtest/locustfile.py --host http://13.124.253.43  → http://localhost:8089
- HelloUser: 백엔드(nginx+Spring) 자체 처리량. AI를 거치지 않는다.
- ChatUser: 실제 질문 경로(Spring → FastAPI RAG → Modal vLLM). Modal GPU 비용이 든다.
  UI의 "User classes"에서 하나만 골라 따로 돌린다.

테스트 기록 삭제(EC2): docker compose exec db psql -U $DB_USER -d fourleaf \
  -c "DELETE FROM chat_logs WHERE session_id LIKE 'loadtest-%';"
"""

import random
import uuid

from locust import HttpUser, between, task

# eval/student_eval_dataset.json 에서 고른 실제 학생 질문
QUESTIONS = [
    "인공지능컴퓨팅전공(인컴)의 전공필수 과목이 뭐가 있어?",
    "수강정정 기간에는 뭘 할 수 있어?",
    "컴퓨터학부 지도교수 확인하고 변경하려면 어떻게 해?",
    "2026학번 신입생 수강꾸러미 신청은 어떻게 해?",
    "학칙 개정으로 수강신청 제도가 어떻게 바뀌어?",
    "학·석사연계과정 신청하려면 자격이랑 기간이 어떻게 돼?",
    "인컴 2027년 2월 졸업예정자는 졸업 준비로 뭘 해야 돼?",
    "IT대학 인권·젠더 대면교육 꼭 들어야 해? 못 가면 어떻게 해?",
    "2학기 등록금 감면장학금 우선선발대상자는 누가 언제 신청해?",
    "이번 2학기 지도교수 상담Week는 언제야?",
]


ERROR_PREFIXES = (
    "AI 모델을 준비하고 있어요",
    "AI 응답을 불러오지 못했습니다",
    "현재 AI 서비스 점검 중",
)


class HelloUser(HttpUser):
    wait_time = between(0.5, 1)

    @task
    def hello(self):
        self.client.get("/api/hello")


class ChatUser(HttpUser):
    # 학생이 답을 읽고 다음 질문을 하는 간격
    wait_time = between(3, 6)

    def on_start(self):
        # 테스트 기록만 골라 지울 수 있도록 session_id에 표시
        self.session_id = f"loadtest-{uuid.uuid4().hex[:8]}"

    @task
    def chat(self):
        with self.client.post(
            "/api/v1/chat",
            json={"message": random.choice(QUESTIONS), "session_id": self.session_id},
            timeout=130,
            catch_response=True,
        ) as res:
            answer = (res.json().get("answer") or "").strip() if res.status_code == 200 else ""
            if res.status_code != 200:
                res.failure(f"HTTP {res.status_code}")
            elif not answer:
                res.failure("빈 답변")
            # 백엔드는 AI 오류(503·타임아웃)도 200 + 안내 문구로 돌려준다.
            elif answer.startswith(ERROR_PREFIXES):
                res.failure(answer[:30])
